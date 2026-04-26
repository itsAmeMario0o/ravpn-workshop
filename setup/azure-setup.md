# Azure setup

Two things to settle before Terraform runs: pick a region with the right capacity, and accept the marketplace terms for the Cisco images. Both are quick. Both will block the deploy if you skip them.

## Pick a region

The FTDv VM uses the Dsv3 family. ISE uses Dsv4. Both are widely available, but not in every region. `eastus2` is a safe default. If you have a regional preference, confirm both families are offered there before you commit.

## Quota check

Each VM is 8 vCPU. You need at least 8 vCPU available in each family.

```bash
az vm list-usage --location eastus2 \
  --query "[?contains(name.value, 'standardDSv3Family') || contains(name.value, 'standardDSv4Family')].{Family:name.localizedValue, Current:currentValue, Limit:limit}" \
  -o table
```

Look at the gap between Current and Limit. If either family has less than 8 vCPU free, request a quota increase via the Azure portal. The request can take hours to days. Do this first.

## Accept marketplace terms

Cisco publishes both images through the Azure Marketplace. Each image has terms you must accept once per subscription before Terraform can deploy a VM that uses it.

```bash
az vm image terms accept --publisher cisco --offer cisco-ftdv --plan cisco-ftdv-x86-byol
az vm image terms accept --publisher cisco --offer cisco-ise-virtual --plan cisco-ise_3_5
```

A note on the FTDv plan name: Cisco publishes FTD 10.x under `cisco-ftdv-x86-byol` (and `-x86-payg`). The older `ftdv-azure-byol` plan only publishes 7.x and earlier. Pick the x86 variant for 10.x.

The FTDv image is BYOL (Bring Your Own License). Smart Licensing handles the actual license activation later, after the device registers with cdFMC.

## Verify

```bash
az vm image terms show --publisher cisco --offer cisco-ftdv --plan cisco-ftdv-x86-byol --query accepted
az vm image terms show --publisher cisco --offer cisco-ise-virtual --plan cisco-ise_3_5 --query accepted
```

Both must return `true`. If either is `false`, Terraform will fail with a marketplace acceptance error.

## What about the resource group?

You do not need to create one. Terraform creates it for you using the name in `terraform.tfvars` (default: `rg-ravpn-demo`).

## A note on Bastion

Bastion is a per-VNet resource. We deploy one Bastion in this VNet and it serves every VM. There is no second jump host and no public IP on FTDv management or ISE. If your team policy forbids Bastion for some reason, you would need to redesign the network module before deploying.
