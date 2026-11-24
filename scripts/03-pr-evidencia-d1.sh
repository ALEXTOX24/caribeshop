#!/usr/bin/env bash
# D1 — Crea en GitHub el pull request que FALLA por Checkov y luego lo corrige.
# Requisitos: estar dentro del repositorio clonado, `gh auth login` hecho y el workflow ya en main.
#   bash scripts/03-pr-evidencia-d1.sh
source "$(dirname "$0")/lib.sh"
need git gh
cd "$ROOT"

gh auth status >/dev/null 2>&1 || die "Primero: gh auth login"
[[ -z "$(git status --porcelain)" ]] || die "Hay cambios sin commit. Haga commit o stash antes."
git ls-files --error-unmatch .github/workflows/terraform-security.yml >/dev/null 2>&1 || die "El workflow no está en el repo."

OUT="$EVID/D1"; mkdir -p "$OUT"
BASE="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#origin/##' || echo main)"
BRANCH="test/checkov-falla-ssh"

git checkout "$BASE" && git pull --ff-only
git checkout -B "$BRANCH"

cat > infra/zz_prueba_insegura.tf <<'EOF'
# PRUEBA D1: regla insegura introducida A PROPÓSITO para demostrar que Checkov bloquea el PR.
# Nunca debe llegar a main.
resource "azurerm_network_security_rule" "ssh_abierto_prueba" {
  name                        = "Allow-SSH-Internet-PRUEBA"
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.app.name
}
EOF
cat > report/D1_PR_EVIDENCIA.md <<'EOF'
# D1 — Evidencia del pipeline bloqueante

1. Commit 1 agrega `infra/zz_prueba_insegura.tf` (SSH 22 abierto desde `*`).
   El workflow `terraform-security` falla en el paso **Checkov (blocking)** con `CKV_AZURE_10`.
2. Commit 2 elimina la regla. El mismo PR pasa `fmt`, `validate` y Checkov y se fusiona.

Capturas y logs: `evidencias/D1/`.
EOF
git add infra/zz_prueba_insegura.tf report/D1_PR_EVIDENCIA.md
git commit -m "Prueba D1: abre SSH a Internet a propósito (Checkov debe bloquear)"
git push -u origin "$BRANCH" --force

PR_URL="$(gh pr create --base "$BASE" --head "$BRANCH" \
  --title "Prueba D1: regla SSH insegura (debe fallar Checkov)" \
  --body "PR de evidencia para D1. El primer commit abre el puerto 22 a Internet a propósito; el pipeline debe fallar en Checkov (CKV_AZURE_10). El segundo commit lo corrige." )"
echo "$PR_URL" | tee "$OUT/pr_url.txt"

log "Esperando el resultado del pipeline (debe FALLAR)…"
sleep 15
gh pr checks "$PR_URL" --watch --interval 15 > "$OUT/checks_fallido.txt" 2>&1 || true
cat "$OUT/checks_fallido.txt"
RUN_ID="$(gh run list --branch "$BRANCH" --limit 1 --json databaseId -q '.[0].databaseId')"
gh run view "$RUN_ID" --log-failed > "$OUT/log_checkov_fallido.txt" 2>&1 || true
grep -n "CKV_AZURE_10\|FAILED" "$OUT/log_checkov_fallido.txt" | head -5 || true
log "TOME CAPTURA de la pestaña 'Checks' del PR en el navegador: $PR_URL"
read -r -p "Presione Enter cuando haya tomado la captura para aplicar la corrección… " _

git rm -q infra/zz_prueba_insegura.tf
git commit -m "Corrige D1: elimina la regla SSH insegura"
git push

log "Esperando el resultado del pipeline (debe PASAR)…"
sleep 15
gh pr checks "$PR_URL" --watch --interval 15 > "$OUT/checks_exitoso.txt" 2>&1 || true
cat "$OUT/checks_exitoso.txt"
log "TOME CAPTURA del PR con los checks en verde."
read -r -p "Presione Enter para fusionar (merge) el PR… " _
gh pr merge "$PR_URL" --merge --delete-branch
git checkout "$BASE" && git pull --ff-only
log "PR de D1 cerrado. El segundo PR se crea al subir las evidencias: bash scripts/04-pr-evidencias.sh"
