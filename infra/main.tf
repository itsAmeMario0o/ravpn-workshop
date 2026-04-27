# Root configuration for the RAVPN workshop environment.
#
# This file wires the modules together. Each module owns one piece of the
# environment: network has the VNet and subnets, ftdv has the firewall,
# ise has the RADIUS server, app has the trading dashboard VM, and bastion
# is the only path for admin access. The root just feeds them inputs.
#
# Everything lives in one resource group. Terraform creates it. When you
# run `terraform destroy`, the resource group goes with it, and every
# resource inside disappears at the same time. That's the whole tear-down.

# Azure provider. The empty features block is required by the provider but
# nothing in this demo needs the non-default behavior.
provider "azurerm" {
  features {}
}

# Tags applied to every resource so cost reports and audit tools have
# something to filter by. Three tags total. No demo-date tag - the repo
# is reused across workshops, and a date would just go stale.
locals {
  common_tags = {
    project     = "ravpn-demo"
    environment = "demo"
    owner       = "mario"
  }
}

# The single resource group everything else lives in.
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Network: VNet, six subnets carved out of it, and the NSG that protects
# the outside (Internet-facing) interface of the firewall.
module "network" {
  source = "./modules/network"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  vnet_address_space  = var.vnet_address_space
  tags                = local.common_tags
}

# Azure Bastion. This is how you reach the firewall and ISE for admin.
# Neither has a public IP; Bastion proxies SSH and HTTPS through Azure's
# managed jumphost service so we don't run a jumphost VM ourselves.
module "bastion" {
  source = "./modules/bastion"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = module.network.bastion_subnet_id
  tags                = local.common_tags
}

# FTDv: the firewall. Four NICs (management, diagnostic, outside, inside),
# one public IP on outside, and a Day-0 JSON that bootstraps the device
# to wait for cdFMC registration after first boot.
module "ftdv" {
  source = "./modules/ftdv"

  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  mgmt_subnet_id       = module.network.mgmt_subnet_id
  diagnostic_subnet_id = module.network.diagnostic_subnet_id
  outside_subnet_id    = module.network.outside_subnet_id
  inside_subnet_id     = module.network.inside_subnet_id
  admin_password       = var.ftdv_admin_password
  reg_key              = var.ftdv_reg_key
  nat_id               = var.ftdv_nat_id
  image_plan           = var.ftdv_image_plan
  image_version        = var.ftdv_image_version
  tags                 = local.common_tags
}

# ISE: the RADIUS server in the RAVPN flow.
#
# Disabled in Terraform on 2026-04-27 after five OSProvisioningTimedOut
# failures across ISE 3.3, 3.4, and 3.5 marketplace images, with both
# default and disabled VM agent configurations, and with both password
# and SSH key authentication. Azure's ~20 minute platform timeout for
# OS provisioning fires before the ISE marketplace image's in-guest
# agent reports ready, no matter what the Terraform create path does.
# Cisco TAC case notes confirm the same pattern and recommend portal
# deployment as the workaround until the marketplace image is updated.
#
# The ISE VM is now deployed manually through the Azure Portal. See
# `setup/ise-portal-deploy.md` for the step-by-step. Once the VM is
# running, it can be imported back into Terraform state with
# `terraform import module.ise.azurerm_linux_virtual_machine.this <id>`.
# The module code under `modules/ise/` is preserved unchanged so that
# import is straightforward when the marketplace image is fixed.
#
# When you uncomment this block, also uncomment the matching outputs in
# outputs.tf.
#
# module "ise" {
#   source = "./modules/ise"
#
#   resource_group_name = azurerm_resource_group.this.name
#   location            = azurerm_resource_group.this.location
#   subnet_id           = module.network.identity_subnet_id
#   admin_password      = var.ise_admin_password
#   dns_domain          = var.ise_dns_domain
#   image_plan          = var.ise_image_plan
#   image_version       = var.ise_image_version
#   tags                = local.common_tags
# }

# Trading app VM. Ubuntu, nginx, with the React build copied in by the
# deploy script. Sits on the inside subnet behind the firewall.
module "app" {
  source = "./modules/app"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = module.network.inside_subnet_id
  admin_username      = var.app_admin_username
  tags                = local.common_tags
}
