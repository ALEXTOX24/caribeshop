variable "prefix" {
  description = "Prefijo corto para recursos globalmente únicos."
  type        = string
  default     = "caribeshop"

  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.prefix))
    error_message = "prefix debe usar solo minúsculas/números y tener entre 3 y 12 caracteres."
  }
}

variable "location" {
  description = "Región Azure para el backend de estado."
  type        = string
  default     = "belgiumcentral"
}

variable "operator_ip" {
  description = "IPv4 pública del operador SIN /32. Se permite en el firewall del Storage del estado."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.operator_ip))
    error_message = "operator_ip debe ser una IPv4, por ejemplo 203.0.113.10."
  }
}
