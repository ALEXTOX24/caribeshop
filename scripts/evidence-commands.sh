#!/usr/bin/env bash
set -euo pipefail

# Ejecutar desde infra/ después del apply, o exportar estas variables manualmente.
if [[ -f ./outputs.tf ]]; then
  RG="$(terraform output -raw resource_group_name)"
  VMSS="$(terraform output -raw vmss_name)"
  PRINCIPAL="$(terraform output -raw vmss_principal_id)"
  KV="$(terraform output -raw key_vault_name)"
  URL="$(terraform output -raw app_url)"
else
  echo "Ejecute desde caribeshop-solution/infra/"
  exit 1
fi

printf '\n== S2: IP públicas por instancia (debe quedar vacío) ==\n'
az vmss list-instance-public-ips -g "$RG" -n "$VMSS" -o table || true

printf '\n== E1: instancias ==\n'
az vmss list-instances -g "$RG" -n "$VMSS" \
  --query "[].{instanceId:instanceId,provisioningState:provisioningState,latestModelApplied:latestModelApplied}" -o table

printf '\n== S4: roles de la identidad VMSS ==\n'
az role assignment list --assignee "$PRINCIPAL" --all -o table

printf '\n== S3: lectura segura del secreto ==\n'
curl -fsS "$URL/secret-check"; echo

printf '\n== Health ==\n'
curl -fsS "$URL/health"; echo

printf '\nKey Vault: %s\n' "$KV"
