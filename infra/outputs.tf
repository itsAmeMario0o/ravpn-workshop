output "resource_group_name" {
  description = "Name of the demo resource group."
  value       = azurerm_resource_group.this.name
}

output "ftdv_outside_public_ip" {
  description = "Public IP of the FTDv outside interface. Set Cloudflare A records to this value."
  value       = module.ftdv.outside_public_ip
}

output "ftdv_mgmt_private_ip" {
  description = "Private IP of the FTDv management interface. Reach via Bastion."
  value       = module.ftdv.mgmt_private_ip
}

output "ise_private_ip" {
  description = "Private IP of the ISE node. Reach via Bastion."
  value       = module.ise.private_ip
}

output "app_private_ip" {
  description = "Private IP of the trading app VM. Reach via Bastion."
  value       = module.app.private_ip
}

output "bastion_name" {
  description = "Bastion resource name. Use with az network bastion tunnel."
  value       = module.bastion.bastion_name
}
