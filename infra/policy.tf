resource "azurerm_policy_definition" "deny_insecure_storage" {
  name         = "deny-storage-without-https-${local.suffix}"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "CaribeShop - Deny Storage Accounts without HTTPS only"
  description  = "Niega Storage Accounts donde supportsHttpsTrafficOnly sea false. Evidencia S5."

  policy_rule = <<-POLICY
    {
      "if": {
        "allOf": [
          {
            "field": "type",
            "equals": "Microsoft.Storage/storageAccounts"
          },
          {
            "field": "Microsoft.Storage/storageAccounts/supportsHttpsTrafficOnly",
            "notEquals": true
          }
        ]
      },
      "then": {
        "effect": "Deny"
      }
    }
  POLICY
}

resource "azurerm_resource_group_policy_assignment" "deny_insecure_storage" {
  name                 = "deny-insecure-storage"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = azurerm_policy_definition.deny_insecure_storage.id
  description          = "S5 - Policy Deny asignada por Terraform al RG de CaribeShop."
  display_name         = "CaribeShop - Deny insecure storage"
}
