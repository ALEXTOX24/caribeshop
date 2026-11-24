resource "azurerm_public_ip" "lb" {
  name                = local.pip_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.public_ip_zones
  tags                = local.common_tags
}

resource "azurerm_lb" "main" {
  name                = local.lb_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "public-frontend"
    public_ip_address_id = azurerm_public_ip.lb.id
  }

  tags = local.common_tags
}

resource "azurerm_lb_backend_address_pool" "app" {
  name            = "app-backend"
  loadbalancer_id = azurerm_lb.main.id
}

resource "azurerm_lb_probe" "health" {
  name                = "health-probe"
  loadbalancer_id     = azurerm_lb.main.id
  protocol            = "Http"
  port                = local.app_port
  request_path        = "/health"
  interval_in_seconds = 5
  number_of_probes    = 2
  probe_threshold     = 1
}

resource "azurerm_lb_rule" "http" {
  name                           = "http"
  loadbalancer_id                = azurerm_lb.main.id
  protocol                       = "Tcp"
  frontend_port                  = local.app_port
  backend_port                   = local.app_port
  frontend_ip_configuration_name = "public-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.app.id]
  probe_id                       = azurerm_lb_probe.health.id
  disable_outbound_snat          = true
  tcp_reset_enabled              = true
}
