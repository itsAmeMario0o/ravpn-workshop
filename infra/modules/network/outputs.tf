output "vnet_id" {
  description = "ID of the demo VNet."
  value       = azurerm_virtual_network.this.id
}

output "mgmt_subnet_id" {
  description = "ID of the management subnet."
  value       = azurerm_subnet.mgmt.id
}

output "diagnostic_subnet_id" {
  description = "ID of the FTDv diagnostic subnet."
  value       = azurerm_subnet.diagnostic.id
}

output "outside_subnet_id" {
  description = "ID of the outside (untrusted) subnet."
  value       = azurerm_subnet.outside.id
}

output "inside_subnet_id" {
  description = "ID of the inside (trusted) subnet hosting the trading app."
  value       = azurerm_subnet.inside.id
}

output "identity_subnet_id" {
  description = "ID of the identity subnet hosting ISE."
  value       = azurerm_subnet.identity.id
}

output "bastion_subnet_id" {
  description = "ID of the AzureBastionSubnet."
  value       = azurerm_subnet.bastion.id
}
