# cdFMC registration

Register FTDv to cdFMC via Security Cloud Control.

## Prerequisites

- Terraform deploy complete. `vm-ftdv` is running.
- Bastion deployed.
- SCC tenant has cdFMC provisioned. From SCC, get the registration command and NAT ID. They were already used as Terraform inputs (`ftdv_reg_key`, `ftdv_nat_id`); the same pair is required at the FTD CLI.

## 1. Wait for FTDv first boot

```bash
az vm get-instance-view -g rg-ravpn-workshop -n vm-ftdv --query "instanceView.statuses[?code=='PowerState/running'].displayStatus" -o tsv
```

Expected: `VM running`. Then wait an additional 15-20 minutes for FTD bootstrap to complete.

## 2. Open Bastion tunnel

```bash
scripts/bastion-tunnel.sh ftdv 50022
```

## 3. SSH to FTDv

```bash
ssh -p 50022 cisco@127.0.0.1
```

Password is the value you put in `ftdv_admin_password`.

You land at the FTD CLI (`>` prompt, not the Linux shell).

## 4. Configure data-interface management

The mgmt NIC has no Internet egress. cdFMC sftunnel must come out of the outside data interface.

```
> configure network management-data-interface
```

Follow the prompts:

- Use the outside interface (typically `GigabitEthernet0/1`).
- Confirm.

## 5. Register to cdFMC

Get the exact `configure manager add` command from SCC. It looks like:

```
> configure manager add <SCC FQDN> <reg_key> <nat_id>
```

The `<reg_key>` and `<nat_id>` must match what you set in `terraform.tfvars`.

## Verify

In cdFMC: **Inventory > Devices**. The FTDv appears within 5-10 minutes and progresses through `Pending Registration` to `Healthy`.

```bash
# At the FTD CLI:
> show managers
```

Expected: the SCC FQDN listed with state `Completed`.

## Troubleshooting

- **Stuck at Pending Registration:** check `nsg-outside` allows TCP 8305 outbound. Confirm `configure network management-data-interface` was run.
- **`configure manager` rejected:** mismatched reg key or NAT ID. Verify against SCC and `terraform.tfvars`.
- **Bastion connection refused:** the FTDv has not finished bootstrap. Wait 5 more minutes.
