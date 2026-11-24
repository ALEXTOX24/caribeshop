resource "azurerm_log_analytics_workspace" "main" {
  name                = local.law_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

resource "azurerm_key_vault" "main" {
  #checkov:skip=CKV_AZURE_189:El requisito S3 pide firewall por subred + IP del operador; el endpoint público permanece habilitado pero default_action=Deny. Private Endpoint queda fuera del alcance del laboratorio.
  #checkov:skip=CKV2_AZURE_32:S3 exige validar el firewall desde una red no autorizada y el laboratorio no contempla Private Endpoint; el acceso queda restringido por subnet/IP y Deny por defecto.
  name                = local.kv_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = true

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = ["${var.operator_ip}/32"]
    virtual_network_subnet_ids = [azurerm_subnet.app.id]
  }

  tags = local.common_tags
}

resource "azurerm_role_assignment" "operator_keyvault" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "keyvault_rbac_propagation" {
  depends_on      = [azurerm_role_assignment.operator_keyvault]
  create_duration = "60s"
}

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!@#%_-+="
}

resource "time_static" "secret_created" {}

resource "time_offset" "secret_expiry" {
  base_rfc3339 = time_static.secret_created.rfc3339
  offset_days  = 90
}

resource "azurerm_key_vault_secret" "db" {
  name            = local.secret_name
  value           = random_password.db.result
  key_vault_id    = azurerm_key_vault.main.id
  content_type    = "CaribeShop demo database password"
  expiration_date = time_offset.secret_expiry.rfc3339

  depends_on = [time_sleep.keyvault_rbac_propagation]

  tags = local.common_tags
}

resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  name                       = "kv-to-log-analytics"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AuditEvent"
  }
}
