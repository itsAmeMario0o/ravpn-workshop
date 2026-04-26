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
