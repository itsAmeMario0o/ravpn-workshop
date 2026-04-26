# Network: VNet, subnets, and the NSG protecting the firewall's outside
# interface.
#
# The address plan: one /16 sliced into six /24 subnets and one /26 for
# Bastion. Each subnet has a single role. Splitting them this way means
# we can attach NSGs and route tables per role without affecting other
# traffic. It also makes the firewall's interfaces map naturally:
# nic0 sits in management, nic1 in diagnostic, nic2 in outside, nic3 in
# inside.

# The single VNet that holds all the demo subnets.
resource "azurerm_virtual_network" "this" {
  name                = "vnet-ravpn"
  address_space       = [var.vnet_address_space]
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Management subnet: FTDv nic0 and ISE GUI live here. No public IPs, no
# Internet egress for management traffic. Bastion is the only way in.
resource "azurerm_subnet" "mgmt" {
  name                 = "snet-management"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.100.0.0/24"]
}

# Diagnostic subnet: FTDv nic1. FTDv requires a NIC in this slot even
# though we don't actively use it for anything in this demo.
resource "azurerm_subnet" "diagnostic" {
  name                 = "snet-diagnostic"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.100.1.0/24"]
}

# Outside subnet: FTDv nic2. This is the one with a public IP. RAVPN
# clients and ZTAA browser traffic land here. The NSG below filters it.
resource "azurerm_subnet" "outside" {
  name                 = "snet-outside"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.100.2.0/24"]
}

# Inside subnet: FTDv nic3 and the trading app VM. Anything the firewall
# protects sits here. No direct Internet exposure.
resource "azurerm_subnet" "inside" {
  name                 = "snet-inside"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.100.3.0/24"]
}

# Identity subnet: ISE only. Separated from management so ISE traffic
# (RADIUS from FTDv, ROPC out to Entra) is easy to filter or audit.
resource "azurerm_subnet" "identity" {
  name                 = "snet-identity"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.100.4.0/24"]
}

# Azure Bastion needs a subnet named exactly AzureBastionSubnet. That's
# not a convention; it's a hard requirement from Azure. Minimum /26.
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.100.5.0/26"]
}

# NSG on the outside subnet. Three rules: TCP 443 inbound (Secure Client
# control + ZTAA browser), UDP 443/500/4500 inbound (Secure Client DTLS
# and IKE), and TCP 8305 outbound (sftunnel back to cdFMC, sourced from
# the data interface because the management interface has no public IP).
resource "azurerm_network_security_group" "outside" {
  name                = "nsg-outside"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Allow inbound HTTPS for Secure Client control plane and the ZTAA
# browser flow. Source is 0.0.0.0/0 because the demo accepts clients
# from anywhere; restrict before production use.
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

# Allow inbound UDP for Secure Client DTLS (443) and IKE (500/4500).
# DTLS is the data plane that carries actual VPN traffic; IKE handles
# session setup and key negotiation.
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

# Allow outbound TCP 8305 (sftunnel) so the firewall can reach cdFMC.
# Sftunnel is the management protocol between FTD and FMC. We route it
# through the data interface because management has no Internet path.
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

# Bind the NSG to the outside subnet.
resource "azurerm_subnet_network_security_group_association" "outside" {
  subnet_id                 = azurerm_subnet.outside.id
  network_security_group_id = azurerm_network_security_group.outside.id
}
