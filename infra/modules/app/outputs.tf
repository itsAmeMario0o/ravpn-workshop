output "private_ip" {
  description = "Private IP of the trading app VM."
  value       = azurerm_network_interface.this.private_ip_address
}

output "vm_id" {
  description = "Trading app VM resource ID."
  value       = azurerm_linux_virtual_machine.this.id
}
