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

# SSH keypair for the ISE VM.
#
# Why generated, not provided: the official Cisco Terraform automation
# module for ISE on Azure uses SSH key authentication (not password) for
# the underlying Linux iseadmin user. Aligning with that pattern matters
# because password-based auth pushes more cloud-init work onto the boot
# path, and that extra work has been observed to push past Azure's ~20
# minute OS-provisioning timeout - which manifests as
# OSProvisioningTimedOut at terraform apply.
#
# Algorithm: RSA 4096. Azure VMs reject Ed25519 keys for the admin user
# even though OpenSSH supports them.
#
# What this key does and does not do:
#  - It DOES protect SSH access to the underlying Linux OS as the iseadmin
#    user. If you bastion-tunnel to ISE on port 22 you authenticate with
#    this key, not a password.
#  - It does NOT change how a workshop attendee signs in to ISE. The ISE
#    GUI on port 443 and the ISE-style CLI both use the password from
#    user_data (var.admin_password). That's a separate auth layer.
#
# Files land in keys/ at the repo root, mode 600 (private) and 644
# (public). The directory is gitignored.
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "private_key" {
  content              = tls_private_key.this.private_key_openssh
  filename             = "${path.root}/../keys/ise_admin"
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "local_file" "public_key" {
  content              = tls_private_key.this.public_key_openssh
  filename             = "${path.root}/../keys/ise_admin.pub"
  file_permission      = "0644"
  directory_permission = "0700"
}

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

  # SSH key auth on the underlying Linux iseadmin user. Matches the
  # official Cisco Terraform automation pattern. Password auth is left
  # at its default (disabled) - var.admin_password is still used, but
  # only inside user_data for the ISE-side admin (GUI and ISE CLI),
  # not for the underlying Linux account.
  admin_ssh_key {
    username   = "iseadmin"
    public_key = tls_private_key.this.public_key_openssh
  }

  network_interface_ids = [azurerm_network_interface.this.id]

  # ISE on Azure reads its bootstrap config from user_data (exposed via
  # the Azure Instance Metadata Service), not custom_data. This matches
  # the official CiscoISE/ciscoise-terraform-automation-azure-nodes
  # module. The bootstrap config sets the ISE admin password, hostname,
  # DNS, NTP, and which APIs to enable.
  user_data = base64encode(local.user_data)

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
