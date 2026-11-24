#!/usr/bin/env bash
# Funciones comunes para los scripts de despliegue y pruebas.
# Se carga con:  source "$(dirname "$0")/../lib.sh"   (o ../lib.sh según la carpeta)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVID="$ROOT/evidencias"
INFRA="$ROOT/infra"
BOOT="$ROOT/bootstrap"
LOADTEST="$ROOT/loadtest"
VENV="$ROOT/.venv"

log() { printf '\033[1;36m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[%s] AVISO:\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\033[1;31m[%s] ERROR:\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }
now_epoch() { date +%s; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_float() { python3 -c "import time; print(f'{time.time():.3f}')"; }

# column puede no existir en instalaciones mínimas: si falta, se imprime tal cual.
tabla() {
  if command -v column >/dev/null 2>&1; then
    column -t "$@"
  elif (( $# > 0 )) && [[ -f "${!#}" ]]; then
    cat "${!#}"
  else
    cat
  fi
}

need() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "Falta '$c'. Ejecute primero: bash scripts/00-instalar-herramientas.sh"
  done
}

activate_venv() {
  if [[ -f "$VENV/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source "$VENV/bin/activate"
  fi
  command -v locust >/dev/null 2>&1 || die "Locust no está instalado. Ejecute: bash scripts/00-instalar-herramientas.sh"
}

my_ip() {
  curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || curl -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true
}

# Lee los outputs de Terraform de infra/ (requiere haber desplegado).
load_outputs() {
  need terraform az jq
  pushd "$INFRA" >/dev/null
  terraform output -json > /tmp/caribeshop-outputs.json 2>/dev/null || die "No hay outputs. ¿Ya corrió scripts/01-desplegar.sh?"
  popd >/dev/null
  local o=/tmp/caribeshop-outputs.json
  RG="$(jq -r '.resource_group_name.value' "$o")"
  VMSS="$(jq -r '.vmss_name.value' "$o")"
  URL="$(jq -r '.app_url.value' "$o")"
  AUTOSCALE="$(jq -r '.autoscale_name.value' "$o")"
  KV="$(jq -r '.key_vault_name.value' "$o")"
  SECRET="$(jq -r '.secret_name.value' "$o")"
  PRINCIPAL="$(jq -r '.vmss_principal_id.value' "$o")"
  LAW="$(jq -r '.log_analytics_workspace_name.value' "$o")"
  LOCATION="$(jq -r '.location.value' "$o")"
  [[ -n "$RG" && "$RG" != "null" ]] || die "No se pudieron leer los outputs de Terraform."
  export RG VMSS URL AUTOSCALE KV SECRET PRINCIPAL LAW LOCATION
}

autoscale_id() {
  az monitor autoscale show -g "$RG" -n "$AUTOSCALE" --query id -o tsv
}

vmss_id() {
  az vmss show -g "$RG" -n "$VMSS" --query id -o tsv
}

# Lista de instancias con zona y estado de salud (JSON).
instances_json() {
  az vmss list-instances -g "$RG" -n "$VMSS" --expand instanceView \
    --query "[].{id:instanceId, name:name, zone:zones[0], provisioning:provisioningState, health:instanceView.vmHealth.status.code, power:instanceView.statuses[1].code}" \
    -o json 2>/dev/null || echo "[]"
}

# Muestreador en segundo plano: cada N s escribe epoch,capacidad,instancias,sanas,ids
# Uso: start_sampler archivo.csv 20 ; ... ; stop_sampler
start_sampler() {
  local out="$1" every="${2:-20}"
  echo "epoch,iso,instances,healthy,running,ids,healthy_ids" > "$out"
  (
    while true; do
      local j e
      e="$(now_epoch)"
      j="$(instances_json)"
      echo "$j" | jq -r --arg e "$e" --arg iso "$(now_iso)" '
        [ $e, $iso,
          (length|tostring),
          ([.[]|select((.health // "")|test("/healthy$";"i"))]|length|tostring),
          ([.[]|select((.power // "")=="PowerState/running")]|length|tostring),
          ([.[].id]|join(" ")),
          ([.[]|select((.health // "")|test("/healthy$";"i"))|.id]|join(" "))
        ] | @csv' >> "$out" 2>/dev/null || true
      sleep "$every"
    done
  ) &
  SAMPLER_PID=$!
  export SAMPLER_PID
}

stop_sampler() {
  if [[ -n "${SAMPLER_PID:-}" ]]; then
    kill "$SAMPLER_PID" 2>/dev/null || true
    wait "$SAMPLER_PID" 2>/dev/null || true
    unset SAMPLER_PID
  fi
}

wait_healthy() {
  # Espera a que haya al menos N instancias sanas (máx. M minutos).
  local n="$1" minutes="${2:-15}" end
  end=$(( $(now_epoch) + minutes * 60 ))
  while (( $(now_epoch) < end )); do
    local h
    h="$(instances_json | jq '[.[]|select((.health // "")|test("/healthy$";"i"))]|length')"
    log "Instancias sanas: $h (se esperan $n)"
    (( h >= n )) && return 0
    sleep 20
  done
  warn "No se alcanzaron $n instancias sanas en $minutes min; se continúa de todos modos."
}

# Exporta la métrica de capacidad observada del autoscale (historial de instancias).
export_autoscale_history() {
  local outdir="$1" hours="${2:-3}"
  local asid
  asid="$(autoscale_id)"
  az monitor metrics list --resource "$asid" --metric ObservedCapacity --interval PT1M \
    --offset "${hours}h" -o json > "$outdir/autoscale_observed_capacity.json" 2>/dev/null || warn "No se pudo exportar ObservedCapacity"
  az monitor activity-log list --resource-id "$asid" --offset "${hours}h" -o json \
    > "$outdir/autoscale_activity_log.json" 2>/dev/null || warn "No se pudo exportar el activity log del autoscale"
  az monitor metrics list --resource "$(vmss_id)" --metric "Percentage CPU" --interval PT1M \
    --offset "${hours}h" --aggregation Average -o json > "$outdir/vmss_cpu.json" 2>/dev/null || warn "No se pudo exportar la CPU del VMSS"
  jq -r '.[] | select(.operationName.value|test("Autoscale";"i")) | [.eventTimestamp, .operationName.localizedValue, .status.localizedValue, (.properties.description // "")] | @tsv' \
    "$outdir/autoscale_activity_log.json" > "$outdir/autoscale_eventos.tsv" 2>/dev/null || true
}

# Desfase de reloj local - reloj de las VMs (s), usando el encabezado Date de la app.
clock_skew() {
  python3 - "$URL" <<'PY'
import sys, time, urllib.request, email.utils
best = None
for _ in range(5):
    a = time.time()
    r = urllib.request.urlopen(sys.argv[1] + "/health", timeout=5)
    b = time.time()
    vm = email.utils.parsedate_to_datetime(r.headers["Date"]).timestamp()
    skew = (a + b) / 2 - (vm + 0.5)       # Date tiene resolución de 1 s
    if best is None or (b - a) < best[0]:
        best = (b - a, skew)
    time.sleep(0.3)
print(f"{best[1]:.2f}")
PY
}

# Ejecuta un comando dentro de una instancia SIN SSH (Run Command) y devuelve el stdout.
run_in_instance() {
  local iid="$1" script="$2"
  az vmss run-command invoke -g "$RG" -n "$VMSS" --instance-id "$iid" \
    --command-id RunShellScript --scripts "$script" \
    --query "value[0].message" -o tsv
}
