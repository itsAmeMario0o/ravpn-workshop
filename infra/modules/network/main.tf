resource "azurerm_virtual_network" "this" {
  name                = "vnet-ravpn"
  address_space       = [var.vnet_address_space]
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "mgmt" {
  name                 = "snet-management"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.100.0.0/24"]
}

resource "azurerm_subnet" "diagnostic" {
  name                 = "snet-diagnostic"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.100.1.0/24"]
}

resource "azurerm_subnet" "outside" {
  name                 = "snet-outside"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.100.2.0/24"]
}

resource "azurerm_subnet" "inside" {
  name                 = "snet-inside"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.100.3.0/24"]
}

resource "azurerm_subnet" "identity" {
  name                 = "snet-identity"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.100.4.0/24"]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.100.5.0/26"]
}

resource "azurerm_network_security_group" "outside" {
  name                = "nsg-outside"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "outside_allow_ravpn_tcp_443" {
  name                        = "Allow-RAVPN-TCP-443"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.outside.name
}

resource "azurerm_network_security_rule" "outside_allow_ravpn_udp" {
  name                        = "Allow-RAVPN-UDP"
  priority                    = 1010
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_ranges     = ["443", "500", "4500"]
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.outside.name
}

resource "azurerm_network_security_rule" "outside_allow_sftunnel_outbound" {
  name                        = "Allow-Sftunnel-Outbound"
  priority                    = 1000
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8305"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.outside.name
}

resource "azurerm_subnet_network_security_group_association" "outside" {
  subnet_id                 = azurerm_subnet.outside.id
  network_security_group_id = azurerm_network_security_group.outside.id
}
