#!/usr/bin/env bash
# Evidencias de configuración: S1, S2, S3, S4, S5, S6, E1, E2, E3, E5, D3.
# Duración: ~5 min (+ hasta 20 min esperando que los logs de Key Vault lleguen a Log Analytics).
#   bash scripts/pruebas/10-evidencias-base.sh
source "$(dirname "$0")/../lib.sh"
load_outputs
set +e   # recolección de evidencias: si un comando falla, se registra y se sigue con el resto
OUT="$EVID/base"; mkdir -p "$OUT"
log "Guardando en $OUT"

{
  echo "Fecha: $(now_iso)"
  echo "Suscripción: $(az account show --query name -o tsv)"
  echo "Grupo de recursos: $RG   Región: $LOCATION"
  echo "URL: $URL"
} > "$OUT/00_contexto.txt"

# S1 — backend remoto y repositorio limpio
{
  echo "== Bloque backend de infra/versions.tf =="; grep -n -A1 'backend "azurerm"' "$INFRA/versions.tf"
  echo; echo "== .gitignore (estado, planes, tfvars) =="; grep -nE 'tfstate|tfplan|tfvars|\.terraform' "$ROOT/.gitignore"
  if [[ -f "$ROOT/.backend.env" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT/.backend.env"
    echo; echo "== Blobs de estado en el backend remoto =="
    az storage blob list --account-name "$STATE_SA" -c tfstate --auth-mode login --query "[].{name:name,size:properties.contentLength,modified:properties.lastModified}" -o table
  fi
  echo; echo "== Archivos de estado/tfvars rastreados por Git (debe quedar vacío) =="
  (cd "$ROOT" && git ls-files 2>/dev/null | grep -E '\.tfstate|\.tfvars$|\.tfplan' || true)
  echo; echo "== Escaneo del historial de Git (debe quedar vacío) =="
  (cd "$ROOT" && git log --all --name-only --pretty=format: 2>/dev/null | grep -E '\.tfstate|(^|/)terraform\.tfvars$' | sort -u || true)
} > "$OUT/S1_estado_remoto.txt" 2>&1

# S2 — sin IP pública, NSG
{
  echo "== IPs públicas de instancias del VMSS (debe quedar vacío) =="
  az vmss list-instance-public-ips -g "$RG" -n "$VMSS" -o table
  echo; echo "== Reglas del NSG =="
  az network nsg list -g "$RG" --query "[0].securityRules[].{prioridad:priority,nombre:name,dir:direction,acceso:access,proto:protocol,puerto:destinationPortRange,origen:sourceAddressPrefix,destino:destinationAddressPrefix}" -o table
} > "$OUT/S2_red_sin_ip_publica.txt" 2>&1

# S3 — lectura del secreto (solo huella) + configuración del Key Vault
{
  echo "== /secret-check (longitud + SHA-256 truncado, nunca el valor) =="
  for _ in 1 2 3; do curl -fsS "$URL/secret-check"; echo; done
  echo; echo "== Key Vault =="
  az keyvault show -n "$KV" --query "{rbac:properties.enableRbacAuthorization,purgeProtection:properties.enablePurgeProtection,softDeleteDias:properties.softDeleteRetentionInDays,firewall:properties.networkAcls.defaultAction,ipsPermitidas:properties.networkAcls.ipRules[].value,subredes:properties.networkAcls.virtualNetworkRules[].id}" -o json
  echo; echo "== Expiración del secreto =="
  az keyvault secret show --vault-name "$KV" -n "$SECRET" --query "{nombre:name,expira:attributes.expires,habilitado:attributes.enabled}" -o table 2>&1 | grep -v '"value"'
} > "$OUT/S3_keyvault_secreto.txt" 2>&1

# S4 — mínimo privilegio
az role assignment list --assignee "$PRINCIPAL" --all \
  --query "[].{rol:roleDefinitionName,alcance:scope}" -o table > "$OUT/S4_roles_identidad_vmss.txt" 2>&1

# S5 — Azure Policy Deny
BAD="badhttp$(date +%s | tail -c 9)"
{
  echo "Asignación de política:"; az policy assignment list -g "$RG" --query "[].{nombre:displayName,efecto:'Deny'}" -o table
  echo; echo "Intento de crear Storage Account $BAD con --https-only false (debe ser RECHAZADO):"
  az storage account create -g "$RG" -n "$BAD" -l "$LOCATION" --sku Standard_LRS --https-only false 2>&1 | head -5
} > "$OUT/S5_policy_deny.txt" 2>&1

# E1 — instancias por zona
instances_json | jq -r '(["instanceId","nombre","zona","salud","estado"]|@tsv), (.[]|[.id,.name,.zone,.health,.power]|@tsv)' \
  | tabla > "$OUT/E1_instancias_zonas.txt"

# E2 — sonda dedicada + métrica Health Probe Status
LB_ID="$(az network lb list -g "$RG" --query "[0].id" -o tsv)"
{
  az network lb probe list -g "$RG" --lb-name "$(basename "$LB_ID")" --query "[].{nombre:name,protocolo:protocol,puerto:port,ruta:requestPath,intervalo:intervalInSeconds,fallos:probeThreshold}" -o table
} > "$OUT/E2_sonda.txt" 2>&1
az monitor metrics list --resource "$LB_ID" --metric DipAvailability --interval PT1M --offset 1h --aggregation Average -o json \
  > "$OUT/E2_health_probe_status.json" 2>/dev/null || true

# E3 — configuración del autoscale
az monitor autoscale show -g "$RG" -n "$AUTOSCALE" -o json > "$OUT/E3_autoscale.json"
az vmss show -g "$RG" -n "$VMSS" --query "{capacidad:sku.capacity,reparacion:automaticRepairsPolicy}" -o json > "$OUT/E4_reparacion_config.json"

# E5 — alerta configurada (el correo recibido se captura en P1)
az monitor metrics alert list -g "$RG" --query "[].{nombre:name,habilitada:enabled,severidad:severity,descripcion:description}" -o table > "$OUT/E5_alertas.txt"

# D3 — instancia configurada sola por cloud-init
{
  echo "== Respuesta de / en varias peticiones (instancias creadas solo con cloud-init) =="
  for _ in 1 2 3 4; do curl -fsS -H 'Connection: close' "$URL/work?iterations=10" | jq -c '{instancia:.instance.name,zona:.instance.zone}'; done
} > "$OUT/D3_cloudinit_app.txt" 2>&1

# S6 — KQL de lectura del secreto por la identidad del VMSS
WS_ID="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query customerId -o tsv)"
log "Generando lecturas del secreto para S6…"
for _ in $(seq 1 10); do curl -fsS "$URL/secret-check" >/dev/null || true; sleep 2; done
QUERY="AzureDiagnostics
| where ResourceProvider == 'MICROSOFT.KEYVAULT' and OperationName == 'SecretGet'
| project TimeGenerated, OperationName, ResultType, CallerIPAddress, identity_claim_oid_g, httpStatusCode_d
| order by TimeGenerated desc
| take 20"
echo "$QUERY" > "$OUT/S6_consulta.kql"
log "Esperando a que los registros lleguen a Log Analytics (puede tardar 5–20 min)…"
for i in $(seq 1 20); do
  az monitor log-analytics query -w "$WS_ID" --analytics-query "$QUERY" -o json > "$OUT/S6_kql_resultado.json" 2>/dev/null || echo "[]" > "$OUT/S6_kql_resultado.json"
  n="$(jq 'length' "$OUT/S6_kql_resultado.json")"
  if (( n > 0 )); then
    log "KQL devolvió $n filas."
    {
      echo "principal_id del VMSS: $PRINCIPAL"; echo
      jq -r '(["TimeGenerated","Operacion","Resultado","IP","identity_oid","http"]|@tsv), (.[]|[.TimeGenerated,.OperationName,.ResultType,.CallerIPAddress,.identity_claim_oid_g,.httpStatusCode_d]|@tsv)' "$OUT/S6_kql_resultado.json" | tabla
      echo; echo "Coinciden con el VMSS: $(jq --arg p "$PRINCIPAL" '[.[]|select(.identity_claim_oid_g==$p)]|length' "$OUT/S6_kql_resultado.json") filas"
    } > "$OUT/S6_kql_resultado.txt"
    break
  fi
  log "Aún sin filas (intento $i/20); reintento en 60 s"
  sleep 60
done

log "Listo. Revise los archivos en $OUT"
ls -1 "$OUT"
