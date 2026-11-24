#!/usr/bin/env bash
set -euo pipefail

LOCATION="${1:-eastus2}"
SKU="${2:-Standard_D2s_v5}"

echo "== Cuenta Azure =="
az account show --query '{subscription:name, subscriptionId:id, tenantId:tenantId}' -o table

echo
echo "== Zonas disponibles para $SKU en $LOCATION =="
az vm list-skus --location "$LOCATION" --size "$SKU" --all \
  --query "[].{name:name,zones:locationInfo[0].zones,restrictions:restrictions}" -o json

echo
echo "== Cuota regional =="
az vm list-usage -l "$LOCATION" -o table

echo
echo "== IP pública detectada =="
python3 - <<'PY'
import urllib.request
try:
    print(urllib.request.urlopen('https://api.ipify.org', timeout=5).read().decode())
except Exception as exc:
    print('No se pudo detectar automáticamente:', type(exc).__name__)
    print('Consulte su IPv4 pública por otro medio y póngala SIN /32 en operator_ip.')
PY
