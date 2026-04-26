# Azure Bastion: the only path for admin access to the firewall, ISE,
# and the trading app VM.
#
# Bastion is a managed PaaS jumphost. You don't run a VM for it - Azure
# handles the infrastructure. From your laptop you call
# `az network bastion tunnel ...` and Bastion proxies the connection to
# a target VM's private IP. No SSH keys exposed to the Internet, no
# jumphost VM to patch, no public IP on the targets.
#
# Standard SKU is required because the Basic SKU doesn't support
# tunneling (the feature we use to SCP files and SSH to FTDv from
# scripts/bastion-tunnel.sh and scripts/deploy-trading-app.sh).

# Public IP for Bastion itself. Bastion needs one - it's how clients
# reach it from the Internet.
resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# The Bastion service. tunneling_enabled = true is what lets the CLI
# tunnel command work. Without it you can only use the Bastion web UI,
# which doesn't help when you're trying to SCP a directory to a VM.
resource "azurerm_bastion_host" "this" {
  name                = "bastion-ravpn"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tunneling_enabled   = true

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = var.subnet_id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  tags = var.tags
}
