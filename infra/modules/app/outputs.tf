output "private_ip" {
  description = "Private IP of the trading app VM."
  value       = azurerm_network_interface.this.private_ip_address
}

output "vm_id" {
  description = "Trading app VM resource ID."
  value       = azurerm_linux_virtual_machine.this.id
}

output "ssh_private_key_path" {
  description = "Local path to the generated SSH private key for the trading app VM."
  value       = local_sensitive_file.private_key.filename
}
