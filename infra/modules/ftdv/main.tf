# FTDv: the firewall.
#
# This module deploys one Cisco Secure Firewall Threat Defense Virtual
# (FTDv) appliance with four NICs, one public IP, and a Day-0 JSON payload
# that bootstraps the device on first boot.
#
# A few things that are easy to get wrong if you've never deployed FTDv on
# Azure:
#
#   1. NIC ORDER MATTERS. Cisco assigns a fixed role to each NIC slot:
#      nic0 = management, nic1 = diagnostic, nic2 = outside (Gi0/1),
#      nic3 = inside (Gi0/2). If you swap them, FTDv boots into a useless
#      state. The module pins them in the right order in the VM resource.
#
#   2. The management NIC has no public IP. Admin access is through Azure
#      Bastion. The cdFMC management traffic (sftunnel, TCP 8305) sources
#      from the data interface (outside) instead of management - the
#      `configure network management-data-interface` command on the FTD CLI
#      sets that up after first boot.
#
#   3. The Day-0 JSON tells FTDv how to bootstrap. ManageLocally=No means
#      "expect a remote manager." FmcIp=DONTRESOLVE means "wait, I'll get
#      manager details later via `configure manager add`." That manual
#      registration is documented in setup/cdFMC-registration.md.
#
#   4. Accelerated networking is on for outside and inside NICs. It's a
#      free performance bump for data-plane traffic. Management and
#      diagnostic don't need it.

# Day-0 JSON payload, base64-encoded into custom_data on the VM. FTDv
# reads this on first boot and configures itself accordingly.
#
# Field names verified against CiscoDevNet/cisco-ftdv 10.0.0 README.
# Note: FmcIp (not FmcIpAddress, which older docs sometimes use) and no
# FirewallMode field in 10.x.
locals {
  day0_json = jsonencode({
    AdminPassword = var.admin_password
    Hostname      = "ftdv-ravpn"
    ManageLocally = "No"
    Diagnostic    = "OFF"
    FmcIp         = "DONTRESOLVE"
    FmcRegKey     = var.reg_key
    FmcNatId      = var.nat_id
  })
}

# Public IP on the outside interface. Static so the IP doesn't change on
# VM restarts - Cloudflare A records and Secure Client profiles point at
# this address, and rotating it would break everything.
resource "azurerm_public_ip" "outside" {
  name                = "pip-ftdv-outside"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# nic0: management. Static private IP, no public IP. Reachable through
# Bastion only. The FTDv admin web UI and SSH live here.
resource "azurerm_network_interface" "mgmt" {
  name                = "nic-ftdv-mgmt"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = var.mgmt_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.100.0.10"
  }
}

# nic1: diagnostic. Required by FTDv even though we don't actively use it.
# The Day-0 JSON sets Diagnostic=OFF so the device doesn't expect this
# interface to be configured separately.
resource "azurerm_network_interface" "diagnostic" {
  name                = "nic-ftdv-diag"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = var.diagnostic_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.100.1.10"
  }
}

# nic2: outside. The Internet-facing interface. Public IP attached. RAVPN
# clients and ZTAA browser traffic terminate here. ip_forwarding_enabled
# is required so the firewall can route between interfaces.
resource "azurerm_network_interface" "outside" {
  name                           = "nic-ftdv-outside"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  accelerated_networking_enabled = true
  ip_forwarding_enabled          = true
  tags                           = var.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = var.outside_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.100.2.10"
    public_ip_address_id          = azurerm_public_ip.outside.id
  }
}

# nic3: inside. The protected side. Sees decrypted traffic between the
# firewall and the trading app. ip_forwarding_enabled for routing.
resource "azurerm_network_interface" "inside" {
  name                           = "nic-ftdv-inside"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  accelerated_networking_enabled = true
  ip_forwarding_enabled          = true
  tags                           = var.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = var.inside_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.100.3.10"
  }
}

# The FTDv VM itself. The image comes from the Cisco marketplace plan;
# the four NICs attach in fixed order (mgmt, diag, outside, inside);
# the Day-0 JSON gets fed in as base64-encoded custom_data.
#
# admin_username is "cisco" because Azure reserves "admin" as a username.
# The actual FTDv admin login - what you'd use to SSH or sign in to the
# FTD web UI - is set by AdminPassword in the Day-0 JSON, not by Azure's
# admin_username field. The two are separate concerns.
resource "azurerm_linux_virtual_machine" "this" {
  name                = "vm-ftdv"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = "cisco"
  admin_password      = var.admin_password

  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.mgmt.id,
    azurerm_network_interface.diagnostic.id,
    azurerm_network_interface.outside.id,
    azurerm_network_interface.inside.id,
  ]

  custom_data = base64encode(local.day0_json)

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "cisco"
    offer     = "cisco-ftdv"
    sku       = var.image_plan
    version   = var.image_version
  }

  # The plan block is required for marketplace images that have terms.
  # Same plan name as the source_image_reference SKU.
  plan {
    name      = var.image_plan
    publisher = "cisco"
    product   = "cisco-ftdv"
  }

  # Boot diagnostics with a managed storage account. Useful when first
  # boot doesn't go as expected - you can grab serial console output.
  boot_diagnostics {}

  tags = var.tags
}
