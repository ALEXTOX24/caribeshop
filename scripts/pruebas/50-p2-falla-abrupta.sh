#!/usr/bin/env bash
# P2.2 — Falla abrupta: se elimina una instancia durante carga moderada.
# Mide errores y el tiempo hasta recuperar la capacidad mínima (2 instancias sanas).
# Duración: ~14 min.
#   bash scripts/pruebas/50-p2-falla-abrupta.sh
# Opcional: MODERATE_USERS=20
source "$(dirname "$0")/../lib.sh"
load_outputs
activate_venv

OUT="$EVID/P2/falla_abrupta"; mkdir -p "$OUT"
CAP="$EVID/P1/capacidad/resumen_capacidad.csv"
if [[ -z "${MODERATE_USERS:-}" && -f "$CAP" ]]; then
  U1="$(awk -F, 'NR>1 && $3<=1000 && $5<=5 {u=$1} END{print u+0}' "$CAP")"
  MODERATE_USERS=$(( U1 * 6 / 10 ))
fi
MODERATE_USERS="${MODERATE_USERS:-20}"; (( MODERATE_USERS < 10 )) && MODERATE_USERS=10
BEFORE="${P2_BEFORE:-120}"; AFTER="${P2_AFTER:-720}"; DURATION=$(( BEFORE + AFTER ))

az monitor autoscale update -g "$RG" -n "$AUTOSCALE" --enabled true --only-show-errors >/dev/null
wait_healthy 2 15
instances_json > "$OUT/instancias_antes.json"
IID="$(jq -r '.[0].id' "$OUT/instancias_antes.json")"
INAME="$(jq -r '.[0].name' "$OUT/instancias_antes.json")"
BEFORE_IDS="$(jq -r '[.[].id]|join(" ")' "$OUT/instancias_antes.json")"
log "Instancia a eliminar: id=$IID nombre=$INAME   Usuarios Locust: $MODERATE_USERS"

start_sampler "$OUT/instancias.csv" 15
trap 'stop_sampler; kill ${LOCUST_PID:-} ${PROBE_PID:-} 2>/dev/null || true' EXIT

T_START="$(now_epoch)"
locust -f "$LOADTEST/locustfile.py" --host "$URL" --headless --only-summary \
  -u "$MODERATE_USERS" -r 10 -t "${DURATION}s" \
  --csv "$OUT/locust" --csv-full-history --html "$OUT/locust.html" >/dev/null 2>&1 &
LOCUST_PID=$!
python3 "$LOADTEST/sonda_trafico.py" --url "$URL" --duration "$DURATION" --out "$OUT/sonda.csv" &
PROBE_PID=$!

sleep "$BEFORE"
T0="$(now_float)"
log "Eliminando la instancia $IID (T0=$T0)"
az vmss delete-instances -g "$RG" -n "$VMSS" --instance-ids "$IID" --no-wait --only-show-errors

RECOVERED_AT=""
for _ in $(seq 1 60); do
  j="$(instances_json)"
  healthy="$(jq '[.[]|select((.health // "")|test("/healthy$";"i"))]|length' <<<"$j")"
  ids="$(jq -r '[.[].id]|join(" ")' <<<"$j")"
  new=""
  for i in $ids; do grep -qw "$i" <<<"$BEFORE_IDS" || new="$new $i"; done
  log "Sanas: $healthy  ids: $ids  nuevas:${new:- ninguna}"
  if (( healthy >= 2 )) && [[ -n "$new" ]] && ! grep -qw "$IID" <<<"$ids"; then
    RECOVERED_AT="$(now_float)"
    log "Capacidad mínima recuperada."
    break
  fi
  sleep 15
done

wait "$LOCUST_PID" 2>/dev/null || true
wait "$PROBE_PID" 2>/dev/null || true
stop_sampler
instances_json > "$OUT/instancias_despues.json"
export_autoscale_history "$OUT" 1

jq -n --arg iid "$IID" --arg name "$INAME" --arg t0 "$T0" --arg rec "$RECOVERED_AT" --arg start "$T_START" --arg users "$MODERATE_USERS" \
  '{prueba:"falla_abrupta", instancia_id:$iid, instancia_nombre:$name, t0:($t0|tonumber), inicio:($start|tonumber),
    recuperada_epoch:($rec|tonumber? // null), usuarios_locust:($users|tonumber)}' > "$OUT/eventos.json"
cat "$OUT/eventos.json"
log "Siguiente: bash scripts/pruebas/60-p3-seguridad.sh"
