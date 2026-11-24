#!/usr/bin/env bash
# Revisa que NO se vaya a subir a Git ningún estado de Terraform, plan, tfvars real ni llave privada.
# Solo mira los archivos que Git subiría (rastreados + nuevos no ignorados).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  files="$(git ls-files -co --exclude-standard)"
else
  files="$(find . -type f -not -path './.git/*' -not -path '*/.terraform/*' -not -path './.venv/*' | sed 's#^\./##')"
fi

bad=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$f" in
    *.tfstate|*.tfstate.*|*.tfplan|*.pem|*.key|*terraform.tfvars|*.auto.tfvars|.backend.env)
      echo "PELIGRO: archivo sensible/generado que se subiría: $f"; bad=1 ;;
  esac
done <<< "$files"

# Patrones de credenciales dentro de los archivos que se subirían (se omiten .md y binarios)
while IFS= read -r f; do
  [[ -z "$f" || "$f" == *.md || ! -f "$f" ]] && continue
  if grep -IlE '(client_secret\s*=\s*"[^$]|-----BEGIN (RSA|OPENSSH|EC) PRIVATE KEY-----|AccountKey=[A-Za-z0-9+/=]{20,})' "$f" >/dev/null 2>&1; then
    echo "PELIGRO: posible credencial en $f"; bad=1
  fi
done <<< "$files"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  hist="$(git log --all --name-only --pretty=format: | grep -E '\.tfstate|(^|/)terraform\.tfvars$|\.tfplan$' | sort -u || true)"
  if [[ -n "$hist" ]]; then
    echo "PELIGRO: el HISTORIAL de Git contiene archivos sensibles:"; echo "$hist"; bad=1
  fi
fi

if [[ "$bad" -ne 0 ]]; then
  exit 1
fi
echo "OK: no se detectaron tfstate/planes/tfvars reales/llaves privadas ni patrones obvios de secretos."
