# ISE: Cisco Identity Services Engine.
#
# In this demo ISE has one job: be the RADIUS server in the RAVPN flow.
# Users connect with Cisco Secure Client, the firewall sends a RADIUS
# request to ISE, ISE checks the credentials against Entra ID over OAuth
# ROPC, and returns Accept or Reject.
#
# This is an Extra Small PSN-only deployment. ISE has multiple personas
# in production (PAN, MnT, PSN, pxGrid). For the demo, the single node
# wears the PSN hat (Policy Service Node, the one that handles RADIUS).
# That keeps memory and disk requirements modest.
#
# First boot takes 45-60 minutes. ISE installs and self-configures during
# that window; trying to reach the GUI before it finishes returns a
# certificate error or a connection refusal.

# User data is plaintext key=value pairs, base64-encoded. ISE reads this
# at first boot and uses it for hostname, DNS, NTP, timezone, the admin
# password, and which APIs to enable. ERS, OpenAPI, and pxGrid are all
# turned on so ISE can be configured programmatically later.
locals {
  user_data = <<-EOT
    hostname=ise-ravpn
    primarynameserver=168.63.129.16
    dnsdomain=${var.dns_domain}
    ntpserver=time.windows.com
    timezone=UTC
    password=${var.admin_password}
    ersapi=yes
    openapi=yes
    pxGrid=yes
    pxgrid_cloud=yes
  EOT
}

# Single NIC for ISE. Lives on the identity subnet, accessible to the
# firewall (RADIUS) and to admin sessions through Bastion.
resource "azurerm_network_interface" "this" {
  name                = "nic-ise"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.100.4.10"
  }
}

# The ISE VM. Standard_D8s_v4 hits the Extra Small PSN-only sizing target
# (8 vCPU, 32 GB RAM). The 300 GB disk is a Cisco minimum - smaller and
# the bootstrap fails halfway through.
resource "azurerm_linux_virtual_machine" "this" {
  name                = "vm-ise"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = "iseadmin"
  admin_password      = var.admin_password

  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.this.id]

  custom_data = base64encode(local.user_data)

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 300
  }

  source_image_reference {
    publisher = "cisco"
    offer     = "cisco-ise-virtual"
    sku       = var.image_plan
    version   = var.image_version
  }

  plan {
    name      = var.image_plan
    publisher = "cisco"
    product   = "cisco-ise-virtual"
  }

  boot_diagnostics {}

  tags = var.tags
}
