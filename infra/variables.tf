variable "prefix" {
  description = "Prefijo de los recursos."
  type        = string
  default     = "caribeshop"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,18}$", var.prefix))
    error_message = "prefix debe usar minúsculas, números o guiones y tener entre 3 y 18 caracteres."
  }
}

variable "location" {
  description = "Región Azure. Debe soportar Availability Zones para cumplir E1."
  type        = string
  default     = "belgiumcentral"
}

variable "zones" {
  description = "Zonas de disponibilidad del VMSS."
  type        = list(string)
  default     = ["1", "2"]

  validation {
    condition     = length(var.zones) >= 2
    error_message = "E1 exige al menos dos zonas."
  }
}

variable "public_ip_zones" {
  description = "Zonas del Standard Public IP. En belgiumcentral se usan 1,2,3 para IP zonal-redundante."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "vm_sku" {
  description = "SKU de las instancias del VMSS. Ajustar si la suscripción no tiene cuota."
  type        = string
  default     = "Standard_D2as_v4"
}

variable "min_instances" {
  description = "Mínimo de instancias productivas."
  type        = number
  default     = 2

  validation {
    condition     = var.min_instances >= 2
    error_message = "E1 exige mínimo 2 instancias."
  }
}

variable "max_instances" {
  description = "Máximo de instancias. Revise cuota antes de aumentar."
  type        = number
  default     = 4

  validation {
    condition     = var.max_instances >= 2
    error_message = "max_instances debe ser al menos 2."
  }
}

variable "operator_ip" {
  description = "IPv4 pública del operador SIN /32. Se usa en el firewall de Key Vault."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.operator_ip))
    error_message = "operator_ip debe ser una IPv4, por ejemplo 203.0.113.10."
  }
}

variable "alert_email" {
  description = "Correo que recibirá la alerta de Azure Monitor."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email debe tener formato de correo válido."
  }
}

variable "admin_username" {
  description = "Usuario local del SO. SSH no se expone por red."
  type        = string
  default     = "azureadmin"
}

variable "ssh_public_key" {
  description = "Llave SSH pública para el usuario local; el puerto 22 permanece bloqueado."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Etiquetas adicionales."
  type        = map(string)
  default = {
    project     = "CaribeShop"
    environment = "lab"
    managed_by  = "Terraform"
  }
}
