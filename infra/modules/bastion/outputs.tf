output "bastion_name" {
  description = "Bastion resource name. Use with `az network bastion tunnel`."
  value       = azurerm_bastion_host.this.name
}

output "bastion_id" {
  description = "Bastion resource ID."
  value       = azurerm_bastion_host.this.id
}
