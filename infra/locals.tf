resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  suffix       = random_string.suffix.result
  clean_prefix = substr(replace(var.prefix, "/[^a-z0-9]/", ""), 0, 14)

  rg_name     = "rg-${var.prefix}-${local.suffix}"
  vnet_name   = "vnet-${var.prefix}"
  subnet_name = "snet-app"
  nsg_name    = "nsg-${var.prefix}-app"
  pip_name    = "pip-${var.prefix}"
  lb_name     = "lb-${var.prefix}"
  vmss_name   = "vmss-${var.prefix}"
  kv_name     = substr("kv-${local.clean_prefix}-${local.suffix}", 0, 24)
  law_name    = "law-${var.prefix}-${local.suffix}"
  secret_name = "db-password"
  app_port    = 80

  common_tags = merge(var.tags, {
    workshop = "seguridad-escalamiento-alta-disponibilidad"
  })
}
