# cdFMC registration

The FTDv we just deployed knows nothing about its manager yet. This step connects it to cdFMC so policy, monitoring, and the VPN dashboard work.

This is the FTDv-side half of registration. The SCC-side half — creating the pending device record, claiming licenses, generating the reg key and NAT ID — happens earlier in the build. See [scc-onboarding.md](scc-onboarding.md).

There is one twist that catches people every time: the management interface on this FTDv has no public IP. The original Cisco docs assume management has Internet access. Ours does not. Before you can register, you tell FTDv to send sftunnel out the data interface (outside) instead. That is one extra command at the FTD CLI.

## Before you start

- [SCC pre-provisioning is done](scc-onboarding.md). Pending device record exists in SCC, and you have the matching `configure manager add ...` command saved in your password manager.
- Terraform deploy is complete. `vm-ftdv` is running.
- Bastion is deployed and reachable.
- The reg key and NAT ID are already in your `terraform.tfvars` (`ftdv_reg_key` and `ftdv_nat_id`); the FTD CLI will need the matching pair when you paste `configure manager add`.

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
ssh -p 50022 admin@127.0.0.1
```

The password is whatever you set in `ftdv_admin_password`. You land at the FTD CLI, recognizable by the `>` prompt. This is not a Linux shell — most Linux commands do not work here.

**Important: SSH as `admin`, not `cisco`.** Our Terraform module sets the Azure-side `admin_username` to `cisco` because Azure reserves the literal username `admin` for VM creation. SSH as `cisco` lands at the FX-OS / Linux shell where FTD commands do not exist and sudoers will not let you switch to `admin`. SSH as `admin` (the FTD-internal user, set by Day-0 JSON) lands at the FTD CLI `>` directly. If you accidentally tried `cisco` first and reused local port `50022` from a prior ISE tunnel, you may also need to clear the cached host key with `ssh-keygen -R "[127.0.0.1]:50022"` before the new SSH session will accept FTDv's host key. See the FTDv entry in `LESSONS-LEARNED.md` for the full story.

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

At the FTD CLI, run these three checks:

```
> show managers
```

Expected: the SCC FQDN listed with state `Completed`. This confirms the device is registered and the sftunnel is up.

```
> show version
```

Expected: an FTD version string starting with `10.` (the workshop deploys 10.x). Confirms the image version is what you expect, not an older fallback.

```
> show interface ip brief
```

Expected: the outside interface (typically `GigabitEthernet0/1`) at `10.100.2.10/24` and the inside interface (`GigabitEthernet0/2`) at `10.100.3.10/24`. Confirms FTDv picked up the right Day-0 IPs and that NIC ordering is correct.

## When it gets stuck

- **Stuck at Pending Registration:** the FTD cannot reach SCC. Check that `nsg-outside` permits TCP 8305 outbound, and that you actually ran `configure network management-data-interface` before the manager add.
- **`configure manager add` rejected:** the registration key or NAT ID is wrong. Double-check both against Security Cloud Control and against `terraform.tfvars`. They are case-sensitive.
- **Bastion connection times out:** the FTDv is still booting. Wait five more minutes and try again. If it has been 30 minutes since `terraform apply` and it still times out, check the VM's boot diagnostics for an actual problem.
