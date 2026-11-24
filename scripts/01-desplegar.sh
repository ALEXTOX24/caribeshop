#!/usr/bin/env bash
# Despliega TODO CaribeShop en la suscripción de Azure con la que se hizo `az login`:
#   1) backend remoto del estado (bootstrap/)  2) plataforma (infra/)
#
# Uso:
#   az login
#   ALERT_EMAIL=micorreo@utb.edu.co bash scripts/01-desplegar.sh
# Variables opcionales: LOCATION (belgiumcentral), VM_SKU (Standard_D2as_v4), PREFIX (caribeshop)
source "$(dirname "$0")/lib.sh"
need az terraform jq ssh-keygen curl

LOCATION="${LOCATION:-belgiumcentral}"
VM_SKU="${VM_SKU:-Standard_D2as_v4}"
PREFIX="${PREFIX:-caribeshop}"
BACKEND_ENV="$ROOT/.backend.env"

az account show >/dev/null 2>&1 || die "Primero inicie sesión: az login"
log "Suscripción: $(az account show --query '[name,id]' -o tsv | tr '\t' ' ')"

if [[ -z "${ALERT_EMAIL:-}" ]]; then
  read -r -p "Correo para la alerta de Azure Monitor: " ALERT_EMAIL
fi

OPERATOR_IP="${OPERATOR_IP:-$(my_ip)}"
[[ -n "$OPERATOR_IP" ]] || die "No se pudo detectar su IP pública. Ejecute con OPERATOR_IP=x.x.x.x"
log "IP pública del operador: $OPERATOR_IP"

KEY="$HOME/.ssh/caribeshop_lab"
if [[ ! -f "$KEY.pub" ]]; then
  log "Generando llave SSH local (el puerto 22 NO se abre; solo la exige la VM Linux)"
  mkdir -p "$HOME/.ssh" && ssh-keygen -t ed25519 -N "" -C caribeshop-lab -f "$KEY" >/dev/null
fi

log "Registrando proveedores de recursos (idempotente)"
for ns in Microsoft.Compute Microsoft.Network Microsoft.KeyVault Microsoft.Storage Microsoft.Insights Microsoft.OperationalInsights Microsoft.PolicyInsights Microsoft.AlertsManagement; do
  az provider register --namespace "$ns" --only-show-errors >/dev/null || true
done

log "Cuota de vCPU en $LOCATION (cada $VM_SKU usa 2 vCPU; max_instances=4 => 8 vCPU)"
az vm list-usage -l "$LOCATION" -o table 2>/dev/null | grep -Ei "Total Regional vCPUs|DASv4|Name" || true

# ---------- 1) Backend remoto ----------
cat > "$BOOT/terraform.tfvars" <<EOF
prefix      = "$PREFIX"
location    = "$LOCATION"
operator_ip = "$OPERATOR_IP"
EOF

cd "$BOOT"
if [[ ! -f "$BACKEND_ENV" ]]; then
  log "Creando el backend remoto del estado (bootstrap)…"
  [[ -f backend.tf ]] && mv backend.tf backend.tf.off
  rm -rf .terraform terraform.tfstate terraform.tfstate.backup
  terraform init -input=false
  terraform apply -auto-approve -input=false
  SA_RG="$(terraform output -raw resource_group_name)"
  SA="$(terraform output -raw storage_account_name)"
  cat > "$BACKEND_ENV" <<EOF
STATE_RG=$SA_RG
STATE_SA=$SA
EOF
  mv backend.tf.off backend.tf
  log "Migrando el estado del bootstrap al backend remoto (S1)…"
  sleep 30
  terraform init -input=false -migrate-state -force-copy \
    -backend-config="resource_group_name=$SA_RG" \
    -backend-config="storage_account_name=$SA" \
    -backend-config="container_name=tfstate" \
    -backend-config="key=bootstrap.tfstate" \
    -backend-config="use_azuread_auth=true" \
    -backend-config="use_cli=true"
  rm -f terraform.tfstate terraform.tfstate.backup
else
  log "Backend ya existe ($BACKEND_ENV)."
fi
# shellcheck disable=SC1090
source "$BACKEND_ENV"

# Si la IP del operador cambió (internet de casa), se agrega al firewall del backend.
if ! az storage account show -g "$STATE_RG" -n "$STATE_SA" --query "networkRuleSet.ipRules[].ipAddressOrRange" -o tsv | grep -qx "$OPERATOR_IP"; then
  log "Agregando la IP $OPERATOR_IP al firewall del backend"
  az storage account network-rule add -g "$STATE_RG" --account-name "$STATE_SA" --ip-address "$OPERATOR_IP" --only-show-errors >/dev/null
  sleep 30
fi

# ---------- 2) Plataforma ----------
cat > "$INFRA/terraform.tfvars" <<EOF
prefix          = "$PREFIX"
location        = "$LOCATION"
operator_ip     = "$OPERATOR_IP"
alert_email     = "$ALERT_EMAIL"
ssh_public_key  = "$(cat "$KEY.pub")"
vm_sku          = "$VM_SKU"
min_instances   = 2
max_instances   = ${MAX_INSTANCES:-4}
zones           = ["1", "2"]
public_ip_zones = ["1", "2", "3"]
EOF

cd "$INFRA"
log "terraform init (backend remoto)"
terraform init -input=false -reconfigure \
  -backend-config="resource_group_name=$STATE_RG" \
  -backend-config="storage_account_name=$STATE_SA" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=caribeshop-prod.tfstate" \
  -backend-config="use_azuread_auth=true" \
  -backend-config="use_cli=true"
terraform fmt -check -recursive "$ROOT" || warn "terraform fmt encontró diferencias (corra: terraform fmt -recursive)"
terraform validate
terraform plan -input=false -out caribeshop.tfplan
terraform apply -input=false caribeshop.tfplan
rm -f caribeshop.tfplan

load_outputs
log "Esperando a que la aplicación responda en $URL/health (cloud-init tarda 2–5 min)…"
for _ in $(seq 1 40); do
  if curl -fsS --max-time 5 "$URL/health" >/dev/null 2>&1; then
    log "Aplicación arriba:"
    curl -fsS "$URL/health"; echo
    curl -fsS "$URL/secret-check"; echo
    echo
    log "Despliegue completo. URL: $URL"
    log "Siguiente paso: bash scripts/pruebas/10-evidencias-base.sh"
    exit 0
  fi
  sleep 15
done
warn "La app aún no responde. Espere unos minutos y pruebe: curl $URL/health"
