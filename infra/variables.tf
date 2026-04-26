# Input variables.
#
# These are what the user fills in via terraform.tfvars before running
# `terraform apply`. Variables marked `sensitive = true` are passwords or
# tokens; Terraform redacts them in plan output and never writes them to
# logs (though they DO end up in the state file, which is why state files
# are gitignored).
#
# Defaults exist where a sensible default is obvious. Variables without
# defaults must be set in terraform.tfvars or the deploy fails.

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Name of the resource group that holds the demo environment."
  type        = string
  default     = "rg-ravpn-demo"
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

# FTDv 10.x publishes under the cisco-ftdv-x86-* SKUs. The legacy
# ftdv-azure-* SKUs only ship 7.x and earlier. Validation locks the
# input to the two valid 10.x choices.
variable "ftdv_image_plan" {
  description = "Cisco FTDv 10.x marketplace plan: cisco-ftdv-x86-byol or cisco-ftdv-x86-payg."
  type        = string
  default     = "cisco-ftdv-x86-byol"
  validation {
    condition     = contains(["cisco-ftdv-x86-byol", "cisco-ftdv-x86-payg"], var.ftdv_image_plan)
    error_message = "Plan must be cisco-ftdv-x86-byol or cisco-ftdv-x86-payg."
  }
}

variable "ftdv_image_version" {
  description = "FTDv image version. The 10.x SKUs publish 10.00.140 at time of writing."
  type        = string
  default     = "latest"
}

# ISE plan name. 3.5 is current; 3.4 is still published in case you need
# to match an existing on-prem version for parity.
variable "ise_image_plan" {
  description = "Cisco ISE marketplace plan: cisco-ise_3_4 or cisco-ise_3_5."
  type        = string
  default     = "cisco-ise_3_5"
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
