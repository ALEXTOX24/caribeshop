resource "azurerm_linux_virtual_machine_scale_set" "app" {
  #checkov:skip=CKV_AZURE_97:Azure for Students no tiene habilitada la feature Microsoft.Compute/EncryptionAtHost; se mantienen Secure Boot, vTPM y discos Premium_LRS.
  name                = local.vmss_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.vm_sku
  instances           = var.min_instances
  admin_username      = var.admin_username
  zones               = var.zones
  zone_balance        = true

  disable_password_authentication = true
  upgrade_mode                    = "Automatic"
  health_probe_id                 = azurerm_lb_probe.health.id
  encryption_at_host_enabled      = false
  secure_boot_enabled             = true
  vtpm_enabled                    = true

  automatic_instance_repair {
    enabled      = true
    grace_period = "PT10M"
    action       = "Replace"
  }

  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  network_interface {
    name    = "nic-app"
    primary = true

    ip_configuration {
      name                                   = "ipconfig"
      primary                                = true
      subnet_id                              = azurerm_subnet.app.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.app.id]
    }
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    app_b64       = base64encode(file("${path.module}/../app/app.py"))
    service_b64   = base64encode(file("${path.module}/../app/caribeshop.service"))
    key_vault_url = azurerm_key_vault.main.vault_uri
    secret_name   = azurerm_key_vault_secret.db.name
  }))

  boot_diagnostics {}

  lifecycle {
    # E3: Azure Monitor Autoscale controla la capacidad en tiempo de ejecución.
    ignore_changes = [instances]
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.app,
    azurerm_role_assignment.operator_keyvault,
    azurerm_key_vault_secret.db
  ]

  tags = local.common_tags
}

resource "azurerm_role_assignment" "vmss_keyvault_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine_scale_set.app.identity[0].principal_id
}
