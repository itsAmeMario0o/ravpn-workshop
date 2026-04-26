locals {
  day0_json = jsonencode({
    AdminPassword = var.admin_password
    Hostname      = "ftdv-ravpn"
    ManageLocally = "No"
    FmcIpAddress  = "DONTRESOLVE"
    FmcRegKey     = var.reg_key
    FmcNatId      = var.nat_id
    Diagnostic    = "OFF"
    FirewallMode  = "Routed"
  })
}

resource "azurerm_public_ip" "outside" {
  name                = "pip-ftdv-outside"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

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

  plan {
    name      = var.image_plan
    publisher = "cisco"
    product   = "cisco-ftdv"
  }

  boot_diagnostics {}

  tags = var.tags
}
