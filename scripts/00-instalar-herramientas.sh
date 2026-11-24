#!/usr/bin/env bash
# Instala todo lo necesario para desplegar y probar CaribeShop.
# Windows: correr dentro de Ubuntu (WSL).  Mac: requiere Homebrew.
#   bash scripts/00-instalar-herramientas.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$(uname)" == "Darwin" ]]; then
  command -v brew >/dev/null || { echo "Instale Homebrew primero: https://brew.sh"; exit 1; }
  brew install azure-cli jq gh python@3.12 hashicorp/tap/terraform || true
else
  sudo apt-get update
  sudo apt-get install -y bsdextrautils curl unzip jq git gnupg lsb-release software-properties-common python3 python3-venv python3-pip openssh-client

  # Azure CLI
  if ! command -v az >/dev/null; then
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  fi

  # Terraform (repositorio oficial de HashiCorp)
  if ! command -v terraform >/dev/null; then
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
      | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
    sudo apt-get update && sudo apt-get install -y terraform
  fi

  # GitHub CLI (para los pull requests de evidencia D1)
  if ! command -v gh >/dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update && sudo apt-get install -y gh
  fi
fi

# Extensión de Azure CLI para consultas KQL
az extension add --name log-analytics --only-show-errors 2>/dev/null || az extension update --name log-analytics --only-show-errors || true

# Entorno Python aislado para Locust y los gráficos
python3 -m venv "$ROOT/.venv"
# shellcheck disable=SC1091
source "$ROOT/.venv/bin/activate"
pip install --upgrade pip -q
pip install -q -r "$ROOT/loadtest/requirements.txt" matplotlib pandas checkov

echo
echo "== Versiones instaladas =="
az version --query '"azure-cli"' -o tsv | sed 's/^/az: /'
terraform version | head -1
gh --version | head -1
locust --version
echo
echo "Listo. Siguiente paso:  az login   y luego   bash scripts/01-desplegar.sh"
