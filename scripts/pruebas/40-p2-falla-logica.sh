#!/usr/bin/env bash
# P2.1 — Falla lógica: una instancia empieza a responder 503 en /health durante carga moderada.
# Mide cuánto tarda en dejar de recibir tráfico y cuántas peticiones fallan.
# Después deja la instancia enferma para evidenciar la reparación automática (E4).
# Duración: 10 min de prueba + hasta 30 min esperando la reparación ≈ 40 min.
#   bash scripts/pruebas/40-p2-falla-logica.sh
# Opcional: MODERATE_USERS=20  ESPERAR_REPARACION=0 (no esperar E4)
source "$(dirname "$0")/../lib.sh"
load_outputs
activate_venv

OUT="$EVID/P2/falla_logica"; mkdir -p "$OUT"
CAP="$EVID/P1/capacidad/resumen_capacidad.csv"
if [[ -z "${MODERATE_USERS:-}" && -f "$CAP" ]]; then
  U1="$(awk -F, 'NR>1 && $3<=1000 && $5<=5 {u=$1} END{print u+0}' "$CAP")"
  MODERATE_USERS=$(( U1 * 6 / 10 ))      # ~30 % de la capacidad de 2 instancias
fi
MODERATE_USERS="${MODERATE_USERS:-20}"; (( MODERATE_USERS < 10 )) && MODERATE_USERS=10
ESPERAR_REPARACION="${ESPERAR_REPARACION:-1}"
BEFORE="${P2_BEFORE:-120}"; AFTER="${P2_AFTER:-480}"; DURATION=$(( BEFORE + AFTER ))

az monitor autoscale update -g "$RG" -n "$AUTOSCALE" --enabled true --only-show-errors >/dev/null
wait_healthy 2 15
instances_json > "$OUT/instancias_antes.json"
IID="$(jq -r '[.[]|select((.health // "")|test("/healthy$";"i"))][0].id' "$OUT/instancias_antes.json")"
INAME="$(jq -r --arg i "$IID" '.[]|select(.id==$i).name' "$OUT/instancias_antes.json")"
log "Instancia objetivo: id=$IID nombre=$INAME   Usuarios Locust: $MODERATE_USERS"

SKEW="$(clock_skew 2>/dev/null || echo 0)"
log "Desfase reloj local - VM: ${SKEW} s"
if python3 -c "import sys; sys.exit(0 if abs(float('$SKEW'))<3 else 1)"; then :; else
  warn "El reloj de este PC está desfasado ${SKEW} s. En WSL corrija con: sudo hwclock -s  (el análisis lo compensa)"
fi
start_sampler "$OUT/instancias.csv" 15
trap 'stop_sampler; kill ${LOCUST_PID:-} ${PROBE_PID:-} 2>/dev/null || true' EXIT

T_START="$(now_epoch)"
locust -f "$LOADTEST/locustfile.py" --host "$URL" --headless --only-summary \
  -u "$MODERATE_USERS" -r 10 -t "${DURATION}s" \
  --csv "$OUT/locust" --csv-full-history --html "$OUT/locust.html" >/dev/null 2>&1 &
LOCUST_PID=$!
python3 "$LOADTEST/sonda_trafico.py" --url "$URL" --duration "$DURATION" --out "$OUT/sonda.csv" &
PROBE_PID=$!

log "Carga moderada en curso; la falla se inyecta en $BEFORE s…"
sleep "$BEFORE"
T0_LOCAL_BEFORE="$(now_float)"
VM_OUT="$(run_in_instance "$IID" 'date +%s.%N; touch /tmp/caribeshop-unhealthy; curl -s -o /dev/null -w "%{http_code}" http://localhost/health')"
T0_LOCAL_AFTER="$(now_float)"
T0_VM="$(echo "$VM_OUT" | grep -Eo '[0-9]{10}\.[0-9]+' | head -1)"
log "Falla inyectada. T0 (reloj de la VM) = $T0_VM. Salida: $(echo "$VM_OUT" | tr '\n' ' ' | cut -c1-200)"

wait "$LOCUST_PID" 2>/dev/null || true
wait "$PROBE_PID" 2>/dev/null || true
log "Medición terminada."

REPAIRED_AT=""; NEW_IDS=""
if [[ "$ESPERAR_REPARACION" == "1" ]]; then
  log "E4: se deja la instancia $IID no sana; la reparación automática (gracia 10 min) debe reemplazarla. Esperando hasta 30 min…"
  for _ in $(seq 1 60); do
    ids="$(instances_json | jq -r '[.[].id]|join(" ")')"
    if ! grep -qw "$IID" <<<"$ids"; then
      REPAIRED_AT="$(now_epoch)"; NEW_IDS="$ids"
      log "Instancia $IID reemplazada. Instancias actuales: $ids"
      break
    fi
    sleep 30
  done
  [[ -z "$REPAIRED_AT" ]] && warn "No se observó el reemplazo en 30 min."
fi
stop_sampler

# Si la instancia sigue viva, se devuelve a sana.
if instances_json | jq -r '.[].id' | grep -qx "$IID"; then
  log "Quitando el marcador de falla de la instancia $IID"
  run_in_instance "$IID" 'rm -f /tmp/caribeshop-unhealthy' >/dev/null || true
fi

az vmss get-instance-view -g "$RG" -n "$VMSS" --query "orchestrationServices" -o json > "$OUT/E4_orquestacion.json" 2>/dev/null || true
az monitor activity-log list --resource-group "$RG" --offset 2h \
  --query "[?contains(operationName.value, 'Microsoft.Compute/virtualMachineScaleSets')].{t:eventTimestamp,op:operationName.localizedValue,estado:status.value,quien:caller}" \
  -o table > "$OUT/E4_activity_log.txt" 2>/dev/null || true
instances_json > "$OUT/instancias_despues.json"

jq -n --arg iid "$IID" --arg name "$INAME" --arg t0vm "$T0_VM" --arg tb "$T0_LOCAL_BEFORE" --arg ta "$T0_LOCAL_AFTER" \
  --arg start "$T_START" --arg skew "$SKEW" --arg rep "$REPAIRED_AT" --arg newids "$NEW_IDS" --arg users "$MODERATE_USERS" \
  '{prueba:"falla_logica", instancia_id:$iid, instancia_nombre:$name, t0_vm:($t0vm|tonumber? // null),
    t0_local_antes:($tb|tonumber), t0_local_despues:($ta|tonumber), inicio:($start|tonumber), desfase_reloj_s:($skew|tonumber? // 0),
    reparada_epoch:($rep|tonumber? // null), instancias_tras_reparacion:$newids, usuarios_locust:($users|tonumber)}' \
  > "$OUT/eventos.json"
cat "$OUT/eventos.json"
log "Siguiente: bash scripts/pruebas/50-p2-falla-abrupta.sh"
