#!/usr/bin/env bash
# P1.1 — Capacidad de UNA instancia.
# Apaga el autoscale, deja el VMSS en 1 instancia y sube usuarios en Locust
# hasta que el p95 supere 1 s. Al terminar (o si se interrumpe) restaura todo.
# Duración: ~25–40 min.
#   bash scripts/pruebas/20-p1-capacidad.sh
# Opcional: USERS_LIST="10 20 40 60 80 100 130 160 200 250"  STEP_MINUTES=3
source "$(dirname "$0")/../lib.sh"
load_outputs
activate_venv

USERS_LIST="${USERS_LIST:-10 20 40 60 80 100 130 160 200 250 300}"
STEP_MINUTES="${STEP_MINUTES:-3}"
OUT="$EVID/P1/capacidad"; mkdir -p "$OUT"

restore() {
  stop_sampler
  log "Restaurando: VMSS a 2 instancias y autoscale habilitado"
  az vmss scale -g "$RG" -n "$VMSS" --new-capacity 2 --only-show-errors >/dev/null || true
  az monitor autoscale update -g "$RG" -n "$AUTOSCALE" --enabled true --only-show-errors >/dev/null || true
}
trap restore EXIT

log "Deshabilitando autoscale y escalando a 1 instancia (mínimo = máximo = 1)"
az monitor autoscale update -g "$RG" -n "$AUTOSCALE" --enabled false --only-show-errors >/dev/null
az vmss scale -g "$RG" -n "$VMSS" --new-capacity 1 --only-show-errors >/dev/null
sleep "${SETTLE_SECONDS:-60}"
wait_healthy 1 10
instances_json > "$OUT/instancia_unica.json"
start_sampler "$OUT/instancias.csv" 30

echo "usuarios,rps,p95_ms,p50_ms,error_pct,requests" > "$OUT/resumen_capacidad.csv"
for u in $USERS_LIST; do
  log "Corrida con $u usuarios durante $STEP_MINUTES min…"
  locust -f "$LOADTEST/locustfile.py" --host "$URL" --headless \
    -u "$u" -r "$(( u > 50 ? 25 : 10 ))" -t "${STEP_MINUTES}m" --only-summary \
    --csv "$OUT/u${u}" --csv-full-history --html "$OUT/u${u}.html" >/dev/null 2>&1 || true

  # Métricas de la parte estable: se descarta el primer minuto (rampa).
  read -r rps p95 p50 err reqs < <(python3 - "$OUT/u${u}_stats_history.csv" <<'PY'
import csv, sys
rows = [r for r in csv.DictReader(open(sys.argv[1])) if r["Name"] == "Aggregated"]
t0 = int(rows[0]["Timestamp"]) if rows else 0
span = (int(rows[-1]["Timestamp"]) - t0) if rows else 0
skip = min(60, span // 3)   # se descarta la rampa inicial
st = [r for r in rows if int(r["Timestamp"]) - t0 >= skip and r["95%"] not in ("N/A", "")]
if not st:
    print("0 0 0 100 0"); sys.exit()
rps = sum(float(r["Requests/s"]) for r in st) / len(st)
p95 = sorted(float(r["95%"]) for r in st)[len(st) // 2]   # mediana de los p95 de cada ventana
p50 = sorted(float(r["50%"]) for r in st)[len(st) // 2]
req = int(st[-1]["Total Request Count"]) - int(st[0]["Total Request Count"])
fail = int(st[-1]["Total Failure Count"]) - int(st[0]["Total Failure Count"])
print(f"{rps:.1f} {p95:.0f} {p50:.0f} {100*fail/max(req,1):.2f} {req}")
PY
)
  echo "$u,$rps,$p95,$p50,$err,$reqs" >> "$OUT/resumen_capacidad.csv"
  log "u=$u  RPS=$rps  p95=${p95} ms  error=${err}%"
  if (( ${p95%.*} > 1000 )) || (( ${err%.*} > 5 )); then
    log "p95 superó 1 s (o error > 5 %). Fin de la búsqueda de capacidad."
    break
  fi
  sleep 30   # deja enfriar la CPU entre corridas
done

tabla -s, "$OUT/resumen_capacidad.csv" | tee "$OUT/resumen_capacidad.txt"
log "Resultados en $OUT. Siguiente: bash scripts/pruebas/30-p1-escalonado.sh"
