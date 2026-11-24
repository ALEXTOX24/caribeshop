output "app_url" {
  description = "URL pública de la aplicación."
  value       = "http://${azurerm_public_ip.lb.ip_address}"
}

output "public_ip" {
  value = azurerm_public_ip.lb.ip_address
}

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "location" {
  value = azurerm_resource_group.main.location
}

output "vmss_name" {
  value = azurerm_linux_virtual_machine_scale_set.app.name
}

output "vmss_principal_id" {
  value = azurerm_linux_virtual_machine_scale_set.app.identity[0].principal_id
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "secret_name" {
  value = azurerm_key_vault_secret.db.name
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.main.name
}

output "autoscale_name" {
  value = azurerm_monitor_autoscale_setting.vmss.name
}

output "policy_assignment_id" {
  value = azurerm_resource_group_policy_assignment.deny_insecure_storage.id
}
