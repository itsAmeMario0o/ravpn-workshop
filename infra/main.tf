provider "azurerm" {
  features {}
}

locals {
  common_tags = {
    project     = "ravpn-workshop"
    environment = "demo"
    owner       = var.owner_tag
  }
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

module "network" {
  source = "./modules/network"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  vnet_address_space  = var.vnet_address_space
  tags                = local.common_tags
}

module "bastion" {
  source = "./modules/bastion"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = module.network.bastion_subnet_id
  tags                = local.common_tags
}

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

module "ise" {
  source = "./modules/ise"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = module.network.identity_subnet_id
  admin_password      = var.ise_admin_password
  dns_domain          = var.ise_dns_domain
  image_plan          = var.ise_image_plan
  image_version       = var.ise_image_version
  tags                = local.common_tags
}

module "app" {
  source = "./modules/app"

  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  subnet_id            = module.network.inside_subnet_id
  admin_username       = var.app_admin_username
  admin_ssh_public_key = var.app_admin_ssh_public_key
  tags                 = local.common_tags
}
