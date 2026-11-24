#!/usr/bin/env bash
# Segundo PR: sube evidencias/ y el informe por pull request (pipeline en verde) y lo fusiona.
#   bash scripts/04-pr-evidencias.sh
source "$(dirname "$0")/lib.sh"
need git gh
cd "$ROOT"
gh auth status >/dev/null 2>&1 || die "Primero: gh auth login"

bash scripts/repo-safety-check.sh || die "Revise el aviso de seguridad antes de subir."

BASE="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#origin/##' || echo main)"
BRANCH="evidencias/pruebas-$(date +%Y%m%d)"
git checkout "$BASE" && git pull --ff-only
git checkout -B "$BRANCH"
git add evidencias report README.md
git commit -m "Evidencias de pruebas P1, P2, P3 e informe" || die "No hay cambios para subir."
git push -u origin "$BRANCH" --force
PR_URL="$(gh pr create --base "$BASE" --head "$BRANCH" --title "Evidencias de pruebas e informe" \
  --body "Agrega CSV/HTML de Locust, gráficos y salidas de Azure CLI de las pruebas P1, P2 y P3, y el informe.")"
echo "$PR_URL"
sleep 15
gh pr checks "$PR_URL" --watch --interval 15 || die "El pipeline falló; revise antes de fusionar."
gh pr merge "$PR_URL" --merge --delete-branch
git checkout "$BASE" && git pull --ff-only
log "Listo: segundo PR fusionado."
