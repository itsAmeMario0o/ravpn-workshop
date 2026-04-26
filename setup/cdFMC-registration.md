# cdFMC registration

The FTDv we just deployed knows nothing about its manager yet. This step connects it to cdFMC so policy, monitoring, and the VPN dashboard work.

There is one twist that catches people every time: the management interface on this FTDv has no public IP. The original Cisco docs assume management has Internet access. Ours does not. Before you can register, you tell FTDv to send sftunnel out the data interface (outside) instead. That is one extra command at the FTD CLI.

## Before you start

- Terraform deploy is complete. `vm-ftdv` is running.
- Bastion is deployed and reachable.
- You have the registration command and NAT ID from Security Cloud Control. The same values are in your `terraform.tfvars` (`ftdv_reg_key` and `ftdv_nat_id`); the FTD CLI will need the matching pair.

## 1. Wait for first boot

FTDv takes 15-20 minutes after the VM reaches `running` for the FTD software to finish bootstrapping. Trying to register before that fails confusingly.

```bash
az vm get-instance-view -g rg-ravpn-demo -n vm-ftdv \
  --query "instanceView.statuses[?code=='PowerState/running'].displayStatus" -o tsv
```

You want `VM running`. Then wait 15 more minutes, then try the next step.

## 2. Open a Bastion tunnel to FTDv

```bash
scripts/bastion-tunnel.sh ftdv 50022
```

Leave that terminal open. It holds the tunnel.

## 3. SSH to FTDv

In a second terminal:

```bash
ssh -p 50022 cisco@127.0.0.1
```

The password is whatever you set in `ftdv_admin_password`. You land at the FTD CLI, recognizable by the `>` prompt. This is not a Linux shell — most Linux commands do not work here.

## 4. Configure data-interface management

```
> configure network management-data-interface
```

The CLI prompts you to pick the data interface. Choose the outside interface (typically `GigabitEthernet0/1`). Confirm. The device may briefly drop the management session and come back; that is expected.

## 5. Register to cdFMC

The exact command is the one Security Cloud Control gave you. It looks like this:

```
> configure manager add <SCC FQDN> <reg_key> <nat_id>
```

The `<reg_key>` and `<nat_id>` you paste here must match exactly what you put in `terraform.tfvars`. If they do not match, registration silently fails — the FTD says it is registered, cdFMC never sees it.

## Verify

In Security Cloud Control: **cdFMC > Inventory > Devices**. The FTDv appears within 5-10 minutes. It progresses through `Pending Registration` to `Healthy`.

At the FTD CLI:

```
> show managers
```

Expected: the SCC FQDN listed with state `Completed`.

## When it gets stuck

- **Stuck at Pending Registration:** the FTD cannot reach SCC. Check that `nsg-outside` permits TCP 8305 outbound, and that you actually ran `configure network management-data-interface` before the manager add.
- **`configure manager add` rejected:** the registration key or NAT ID is wrong. Double-check both against Security Cloud Control and against `terraform.tfvars`. They are case-sensitive.
- **Bastion connection times out:** the FTDv is still booting. Wait five more minutes and try again. If it has been 30 minutes since `terraform apply` and it still times out, check the VM's boot diagnostics for an actual problem.
