output "outside_public_ip" {
  description = "Public IP of the FTDv outside interface. Set Cloudflare A records to this."
  value       = azurerm_public_ip.outside.ip_address
}

output "mgmt_private_ip" {
  description = "Private IP of the FTDv management interface."
  value       = azurerm_network_interface.mgmt.private_ip_address
}

output "outside_private_ip" {
  description = "Private IP of the FTDv outside interface."
  value       = azurerm_network_interface.outside.private_ip_address
}

output "inside_private_ip" {
  description = "Private IP of the FTDv inside interface."
  value       = azurerm_network_interface.inside.private_ip_address
}

output "vm_id" {
  description = "FTDv VM resource ID."
  value       = azurerm_linux_virtual_machine.this.id
}
