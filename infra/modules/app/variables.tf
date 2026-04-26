variable "resource_group_name" {
  description = "Resource group for the trading app VM."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the app VM (inside subnet)."
  type        = string
}

variable "admin_username" {
  description = "Admin username for the app VM."
  type        = string
}

variable "vm_size" {
  description = "Azure VM size for the trading app. B1s is sufficient for nginx + static React build."
  type        = string
  default     = "Standard_B1s"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
}
