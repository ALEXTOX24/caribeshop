#!/usr/bin/env bash
# P3 — Pruebas de seguridad.
#   P3.1 Key Vault bloqueado desde red no autorizada (parte en Cloud Shell, ver instrucciones al final)
#   P3.2 Una instancia no puede salir a Internet arbitrario, pero sí a Key Vault
#   P3.3 Violar la Azure Policy Deny
# Duración: ~5 min.
#   bash scripts/pruebas/60-p3-seguridad.sh
source "$(dirname "$0")/../lib.sh"
load_outputs
set +e   # recolección de evidencias: si un comando falla, se registra y se sigue con el resto
OUT="$EVID/P3"; mkdir -p "$OUT"

# P3.1 (contraste) — desde la IP autorizada del operador SÍ se puede (solo se muestran metadatos)
{
  echo "Fecha: $(now_iso)   IP del operador: $(my_ip)"
  echo "Lectura de metadatos del secreto desde la red AUTORIZADA (se omite el valor):"
  az keyvault secret show --vault-name "$KV" -n "$SECRET" --query "{id:id,expira:attributes.expires}" -o json 2>&1
} > "$OUT/P3_1_desde_ip_autorizada.txt"

# P3.2 — egress desde una instancia
IID="$(instances_json | jq -r '.[0].id')"
KV_URI="$(az keyvault show -n "$KV" --query properties.vaultUri -o tsv)"
log "P3.2: probando salida a Internet desde la instancia $IID (Run Command, sin SSH)…"
SCRIPT=$(cat <<EOF
python3 - <<'PY'
import urllib.request, urllib.error
dest = ['https://example.com', 'https://www.google.com', 'https://github.com', '${KV_URI}']
for u in dest:
    try:
        r = urllib.request.urlopen(u, timeout=6)
        print(u, '-> PERMITIDO', r.status)
    except urllib.error.HTTPError as e:
        print(u, '-> ALCANZABLE (HTTP', e.code, ')')
    except Exception as e:
        print(u, '-> BLOQUEADO', type(e).__name__)
PY
echo; echo 'App leyendo Key Vault desde la misma instancia:'; curl -s http://localhost/secret-check
EOF
)
{
  echo "Fecha: $(now_iso)   Instancia: $IID"
  echo "Reglas de salida del NSG:"
  az network nsg list -g "$RG" --query "[0].securityRules[?direction=='Outbound'].{prioridad:priority,nombre:name,acceso:access,puerto:destinationPortRange,destino:destinationAddressPrefix}" -o table
  echo; echo "Resultado dentro de la VM:"
  run_in_instance "$IID" "$SCRIPT"
} > "$OUT/P3_2_egress.txt" 2>&1
cat "$OUT/P3_2_egress.txt"

# P3.3 — Policy Deny
BAD="badhttp$(date +%s | tail -c 9)"
{
  echo "Fecha: $(now_iso)"
  echo "az storage account create -g $RG -n $BAD --https-only false"
  az storage account create -g "$RG" -n "$BAD" -l "$LOCATION" --sku Standard_LRS --https-only false 2>&1 | head -6
} > "$OUT/P3_3_policy_deny.txt"
cat "$OUT/P3_3_policy_deny.txt"

# P3.1 — instrucciones para Cloud Shell
cat > "$OUT/P3_1_COMANDO_CLOUD_SHELL.txt" <<EOF
P3.1 — Abra https://shell.azure.com (Bash) con el MISMO usuario y pegue:

az keyvault secret show --vault-name $KV --name $SECRET --query id -o tsv

Resultado esperado: error "Forbidden ... Client address is not authorized" / ForbiddenByFirewall,
aunque el usuario tiene el rol Key Vault Secrets Officer. Tome CAPTURA de pantalla y guárdela como
evidencias/P3/P3_1_cloud_shell_bloqueado.png. Copie también el texto del error en
evidencias/P3/P3_1_cloud_shell_bloqueado.txt
EOF
echo
cat "$OUT/P3_1_COMANDO_CLOUD_SHELL.txt"
