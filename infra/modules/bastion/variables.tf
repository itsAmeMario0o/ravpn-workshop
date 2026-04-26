variable "resource_group_name" {
  description = "Resource group for Bastion."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "subnet_id" {
  description = "ID of the AzureBastionSubnet (must be named exactly that)."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
}
