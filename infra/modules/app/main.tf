# Trading app VM.
#
# This is a small Ubuntu VM that hosts nginx and a static React build
# (the trading dashboard). It sits on the inside subnet behind the
# firewall, so the only path to it from the Internet is through FTDv.
#
# The app has two routes:
#   /vpn  - dark-themed dashboard, what RAVPN users see after the tunnel
#   /ztaa - light-themed dashboard, what ZTAA users see after SAML+MFA
#
# Both routes run from the same React bundle. The themes are different
# only so the workshop audience can visually tell which path they took.
#
# B1s is intentionally tiny - the app is static files served by nginx,
# so a 1 vCPU / 1 GB RAM VM is plenty.

# SSH keypair for the trading app VM. Generated at apply time so users
# don't have to bring their own. The Ed25519 algorithm is the modern
# default - faster, smaller, more secure than RSA.
#
# Both files land at the repo root in keys/. The directory is gitignored.
# After apply, you can SSH with: ssh -i keys/ravpn_workshop appadmin@<ip>
#
# Trade-off: the private key lives in terraform.tfstate (gitignored). For
# a workshop on a personal laptop, that's acceptable. For production you
# would use Azure Key Vault or a Vault provider instead.
resource "tls_private_key" "this" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "private_key" {
  content              = tls_private_key.this.private_key_openssh
  filename             = "${path.root}/../keys/ravpn_workshop"
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "local_file" "public_key" {
  content              = tls_private_key.this.public_key_openssh
  filename             = "${path.root}/../keys/ravpn_workshop.pub"
  file_permission      = "0644"
  directory_permission = "0700"
}

# Cloud-init: minimal first-boot config. Installs nginx and openssl,
# enables and starts nginx. The actual nginx site config and the React
# build come later via scripts/deploy-trading-app.sh.
locals {
  cloud_init = <<-EOT
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - nginx
      - openssl
    runcmd:
      - systemctl enable nginx
      - systemctl start nginx
  EOT
}

# Single NIC on the inside subnet. Static private IP so the firewall's
# rules for "send ZTAA traffic to the app" can reference a stable
# address.
resource "azurerm_network_interface" "this" {
  name                = "nic-tradingapp"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.100.3.20"
  }
}

# The VM. SSH key auth only (no password). The deploy script reaches
# this VM by tunneling through Bastion - there's no public IP and no
# direct SSH path.
resource "azurerm_linux_virtual_machine" "this" {
  name                = "vm-tradingapp"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [azurerm_network_interface.this.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.this.public_key_openssh
  }

  custom_data = base64encode(local.cloud_init)

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  boot_diagnostics {}

  tags = var.tags
}
