# Outputs surfaced after `terraform apply` finishes.
#
# These values come back as JSON when you run `terraform output`. They're
# what you need for the next steps in the build - update Cloudflare A
# records to the firewall's public IP, ssh through Bastion to the
# private IPs of the FTDv, ISE, and the app VM.

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

# ISE outputs are commented out because ISE is currently deployed via
# the Azure Portal, not Terraform. See setup/ise-portal-deploy.md.
# The portal-assigned private IP is 10.100.4.10 by convention - same
# value the Terraform module would have set. When the module is
# re-enabled and the VM is imported back into state, uncomment these.
#
# output "ise_private_ip" {
#   description = "Private IP of the ISE node. Reach via Bastion."
#   value       = module.ise.private_ip
# }

output "app_private_ip" {
  description = "Private IP of the trading app VM. Reach via Bastion."
  value       = module.app.private_ip
}

output "bastion_name" {
  description = "Bastion resource name. Use with az network bastion tunnel."
  value       = module.bastion.bastion_name
}

output "app_ssh_key_path" {
  description = "Local path to the generated SSH private key for the trading app VM. Use with: ssh -i <path> appadmin@<app_private_ip>."
  value       = module.app.ssh_private_key_path
}

# Commented out alongside ise_private_ip. See note above.
#
# output "ise_ssh_key_path" {
#   description = "Local path to the generated SSH private key for the ISE VM (underlying Linux iseadmin user). The ISE GUI still uses the password from terraform.tfvars."
#   value       = module.ise.ssh_private_key_path
# }
