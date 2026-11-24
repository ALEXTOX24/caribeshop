resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  clean_prefix = substr(replace(var.prefix, "/[^a-z0-9]/", ""), 0, 12)
  suffix       = random_string.suffix.result
  storage_name = substr("tf${local.clean_prefix}${local.suffix}", 0, 24)
  common_tags = {
    project    = "CaribeShop"
    managed_by = "Terraform"
    purpose    = "remote-state"
  }
}

resource "azurerm_resource_group" "state" {
  name     = "rg-${var.prefix}-tfstate-${local.suffix}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_storage_account" "state" {
  #checkov:skip=CKV_AZURE_33:El backend de estado no almacena datos de aplicación; el logging detallado del servicio Blob queda fuera del laboratorio y se protege con ZRS, versionado y retención.
  #checkov:skip=CKV_AZURE_59:El backend requiere endpoint público para que los integrantes operen Terraform; el acceso está restringido por firewall a la IP del operador y usa OAuth/Entra ID.
  #checkov:skip=CKV_AZURE_206:El backend usa ZRS, la replicación regional exigida para este laboratorio; GRS aumentaría el costo sin aportar evidencia adicional.
  #checkov:skip=CKV2_AZURE_1:El backend usa cifrado administrado por la plataforma; CMK requiere un ciclo adicional de Key Vault que no forma parte del alcance del taller.
  #checkov:skip=CKV2_AZURE_33:El backend remoto se accede desde las IPs de los operadores, por lo que un Private Endpoint impediría el flujo de trabajo definido; el firewall mantiene el acceso en Deny por defecto.
  # El endpoint público permanece habilitado, pero el firewall es Deny y solo
  # admite la IP del operador. Es necesario para un backend accesible desde
  # equipos de los integrantes sin una red privada dedicada.
  name                     = local.storage_name
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_tier             = "Standard"
  account_replication_type = "ZRS"
  account_kind             = "StorageV2"

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  public_network_access           = "Enabled"
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = [var.operator_ip]
  }

  tags = local.common_tags
}

resource "azurerm_role_assignment" "operator_blob" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.operator_blob]
  create_duration = "60s"
}

resource "azurerm_storage_container" "tfstate" {
  #checkov:skip=CKV2_AZURE_21:El contenedor solo guarda el estado de Terraform y no datos de aplicación; la retención/versionado del Blob y el acceso privado al contenedor mitigan el riesgo.
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  depends_on = [time_sleep.rbac_propagation]
}
