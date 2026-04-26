variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Name of the resource group that holds the demo environment."
  type        = string
  default     = "rg-ravpn-workshop"
}

variable "vnet_address_space" {
  description = "VNet CIDR. Subnets are derived from this in the network module."
  type        = string
  default     = "10.100.0.0/16"
}

variable "ftdv_admin_password" {
  description = "FTDv admin password (used in Day-0 custom data)."
  type        = string
  sensitive   = true
}

variable "ftdv_reg_key" {
  description = "cdFMC registration key from SCC."
  type        = string
  sensitive   = true
}

variable "ftdv_nat_id" {
  description = "cdFMC NAT ID from SCC."
  type        = string
  sensitive   = true
}

variable "ise_admin_password" {
  description = "ISE admin password (used in user data)."
  type        = string
  sensitive   = true
}

variable "ise_dns_domain" {
  description = "DNS domain for ISE hostname."
  type        = string
  default     = "ravpn.local"
}

variable "app_admin_username" {
  description = "Admin username for the trading app VM."
  type        = string
  default     = "appadmin"
}

variable "app_admin_ssh_public_key" {
  description = "SSH public key for the trading app VM admin user."
  type        = string
}

variable "ftdv_image_plan" {
  description = "Cisco FTDv marketplace plan: ftdv-azure-byol or ftdv-azure-payg."
  type        = string
  default     = "ftdv-azure-byol"
  validation {
    condition     = contains(["ftdv-azure-byol", "ftdv-azure-payg"], var.ftdv_image_plan)
    error_message = "Plan must be ftdv-azure-byol or ftdv-azure-payg."
  }
}

variable "ftdv_image_version" {
  description = "FTDv image version. Pin to a specific 10.x build."
  type        = string
  default     = "latest"
}

variable "ise_image_plan" {
  description = "Cisco ISE marketplace plan: cisco-ise_3_4 or cisco-ise_3_5."
  type        = string
  default     = "cisco-ise_3_4"
  validation {
    condition     = contains(["cisco-ise_3_4", "cisco-ise_3_5"], var.ise_image_plan)
    error_message = "Plan must be cisco-ise_3_4 or cisco-ise_3_5."
  }
}

variable "ise_image_version" {
  description = "ISE image version."
  type        = string
  default     = "latest"
}
