#!/usr/bin/env bash
# Borra todo lo desplegado para no gastar el crédito de Azure.
# Correr SOLO cuando ya estén guardadas todas las evidencias.
#   bash scripts/99-destruir.sh
source "$(dirname "$0")/lib.sh"
need az terraform

read -r -p "Esto borra la plataforma CaribeShop de Azure. Escriba DESTRUIR para continuar: " ok
[[ "$ok" == "DESTRUIR" ]] || die "Cancelado."

cd "$INFRA"
log "terraform destroy de la plataforma…"
terraform destroy -auto-approve -input=false

if [[ -f "$ROOT/.backend.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/.backend.env"
  read -r -p "¿Borrar también el backend del estado ($STATE_RG)? [s/N] " b
  if [[ "$b" =~ ^[sS]$ ]]; then
    az group delete -n "$STATE_RG" --yes --no-wait
    rm -f "$ROOT/.backend.env"
    log "Backend en eliminación (tarda unos minutos)."
  fi
fi

log "Grupos de recursos que quedan en la suscripción:"
az group list --query "[].name" -o tsv
log "Verifique también en el portal que no quede nada de CaribeShop."
