variable "resource_group_name" {
  description = "Resource group for ISE."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the ISE node (identity subnet)."
  type        = string
}

variable "admin_password" {
  description = "ISE admin password used in user data."
  type        = string
  sensitive   = true
}

variable "dns_domain" {
  description = "DNS domain for the ISE hostname."
  type        = string
}

variable "image_plan" {
  description = "Cisco ISE marketplace plan."
  type        = string
}

variable "image_version" {
  description = "ISE image version."
  type        = string
}

variable "vm_size" {
  description = "Azure VM size. ISE Extra Small PSN-only deployment uses Standard_D8s_v4."
  type        = string
  default     = "Standard_D8s_v4"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
}
