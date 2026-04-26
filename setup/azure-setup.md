# Azure setup

Subscription, region, quota, and marketplace terms.

## Region

Pick a region with availability for Dsv3 and Dsv4 families. `eastus2` works.

## Quota check

```bash
az vm list-usage --location eastus2 \
  --query "[?contains(name.value, 'standardDSv3Family') || contains(name.value, 'standardDSv4Family')].{Family:name.localizedValue, Current:currentValue, Limit:limit}" \
  -o table
```

Need at least 8 vCPU available in each family. If short, request a quota increase via the Azure portal (can take hours).

## Marketplace terms

```bash
az vm image terms accept --publisher cisco --offer cisco-ftdv --plan ftdv-azure-byol
az vm image terms accept --publisher cisco --offer cisco-ise-virtual --plan cisco-ise_3_4
```

For BYOL FTDv you also need Cisco Smart Licensing (handled later via cdFMC).

## Verify

```bash
az vm image terms show --publisher cisco --offer cisco-ftdv --plan ftdv-azure-byol --query accepted
az vm image terms show --publisher cisco --offer cisco-ise-virtual --plan cisco-ise_3_4 --query accepted
```

Both must return `true`.

## Resource group

Terraform creates the resource group. No manual step.

## Notes

- Bastion is a per-VNet resource. One Bastion serves all VMs in this VNet.
- The FTDv management interface stays private. Bastion is the only admin path.
