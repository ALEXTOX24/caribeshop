#!/usr/bin/env bash
# P1.2/P1.3 — Perfil escalonado (subida → sostenida → bajada) con autoscale activo,
# registrando instancias en el tiempo para evidenciar scale-out y scale-in (E3)
# y disparar la alerta de CPU (E5).
# Duración: ~35 min de Locust + 20 min observando el scale-in ≈ 55 min.
#   bash scripts/pruebas/30-p1-escalonado.sh
# Opcional: PEAK_USERS=200  POST_MINUTES=20
source "$(dirname "$0")/../lib.sh"
load_outputs
activate_venv

OUT="$EVID/P1/escalonado"; mkdir -p "$OUT"
CAP="$EVID/P1/capacidad/resumen_capacidad.csv"

if [[ -z "${PEAK_USERS:-}" ]]; then
  if [[ -f "$CAP" ]]; then
    # usuarios máximos con p95 <= 1 s en UNA instancia; el pico usa ~2,2x para saturar 2 instancias
    U1="$(awk -F, 'NR>1 && $3<=1000 && $5<=5 {u=$1} END{print u+0}' "$CAP")"
    PEAK_USERS=$(( U1 > 0 ? U1 * 22 / 10 : 180 ))
  else
    PEAK_USERS=180
  fi
fi
(( PEAK_USERS > 450 )) && PEAK_USERS=450
POST_MINUTES="${POST_MINUTES:-20}"
log "Pico de usuarios: $PEAK_USERS"

az monitor autoscale update -g "$RG" -n "$AUTOSCALE" --enabled true --only-show-errors >/dev/null
wait_healthy 2 15

T_START="$(now_epoch)"
echo "$T_START" > "$OUT/inicio_epoch.txt"
start_sampler "$OUT/instancias.csv" 20
trap stop_sampler EXIT

log "Locust: perfil escalonado (~35 min). No cierre esta ventana."
LOCUST_USE_SHAPE=1 LOCUST_PEAK_USERS="$PEAK_USERS" \
  locust -f "$LOADTEST/locustfile.py" --host "$URL" --headless --only-summary \
  --csv "$OUT/step" --csv-full-history --html "$OUT/step.html" 2>&1 | tail -25 | tee "$OUT/locust_resumen.txt"

log "Locust terminó. Observando $POST_MINUTES min más para registrar el scale-in…"
sleep $(( POST_MINUTES * 60 ))
stop_sampler

HOURS=$(( ( $(now_epoch) - T_START ) / 3600 + 1 ))
export_autoscale_history "$OUT" "$HOURS"

# E5 — historial de alertas disparadas
SUB="$(az account show --query id -o tsv)"
az rest --method get \
  --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.AlertsManagement/alerts?api-version=2019-05-05-preview&targetResourceGroup=$RG&timeRange=1d" \
  -o json > "$OUT/E5_alertas_disparadas.json" 2>/dev/null || true
jq -r '.value[]? | [.properties.essentials.startDateTime, .name, .properties.essentials.monitorCondition, .properties.essentials.severity] | @tsv' \
  "$OUT/E5_alertas_disparadas.json" > "$OUT/E5_alertas_disparadas.txt" 2>/dev/null || true

log "Eventos de autoscale:"; cat "$OUT/autoscale_eventos.tsv" 2>/dev/null || true
log "Alertas disparadas:"; cat "$OUT/E5_alertas_disparadas.txt" 2>/dev/null || true
echo
log "Revise su correo ($OUT): tome captura del correo de la alerta de CPU y del autoscale (E5)."
log "Siguiente: bash scripts/pruebas/40-p2-falla-logica.sh"
