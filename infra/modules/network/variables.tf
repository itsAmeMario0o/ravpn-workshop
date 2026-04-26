variable "resource_group_name" {
  description = "Resource group for network resources."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "vnet_address_space" {
  description = "VNet CIDR. Must be at least /22 to accommodate all subnets."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
}
