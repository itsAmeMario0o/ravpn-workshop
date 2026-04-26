# Provider and Terraform version pins.
#
# Pinning matters here because the azurerm provider changes resource
# arguments between minor versions. Without a pin, an unrelated upgrade
# can break the deploy by renaming a field. The `~> 3.116` constraint
# allows 3.116.x patch upgrades but blocks 4.0 (which has known
# breaking changes for some of the resources we use).

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # tls + local generate and write the trading app VM's SSH keypair at
    # apply time. Saves you from having to hand over an existing public key.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
