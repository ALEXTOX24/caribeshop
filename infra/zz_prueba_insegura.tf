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
