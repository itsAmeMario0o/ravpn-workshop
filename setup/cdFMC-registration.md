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

## 4. Convert management interface to manual IP

`configure network management-data-interface` (next step) refuses to run while the management interface is DHCP-assigned. Convert it to manual using the same values Azure already hands it via DHCP. At the FTD `>` prompt:

```
> configure network ipv4 manual 10.100.0.10 255.255.255.0 10.100.0.1
```

The session drops while FTD restarts its management plane. Wait ~30 seconds, re-SSH (`ssh -p 50022 admin@127.0.0.1`), and verify with `show network`:

```
Configuration : Manual
Address       : 10.100.0.10
```

## 5. Configure data-interface management

```
> configure network management-data-interface
```

This is the interactive prompt. Answer with these exact values:

| Prompt | Answer |
|---|---|
| Data interface to use for management | `Ethernet0/1` (FTD 10.x naming, not GigabitEthernet) |
| Specify a name for the interface | accept default `outside` (Enter) |
| IP address (manual / dhcp) | `manual` |
| IPv4/IPv6 address | `10.100.2.10` |
| Netmask/IPv6 Prefix | `255.255.255.0` |
| Default Gateway | `10.100.2.1` |
| Comma-separated list of DNS servers | accept default `168.63.129.16` (Enter) |
| DDNS server update URL | accept default `none` (Enter) |

After confirmation, FTD prints `Setting IPv4 network configuration...` and the management plane resets. Your SSH session **will hang and then drop**. Use `~.` (Enter, then tilde, then period) to break out of the hung session. **Do not Ctrl+C — that doesn't work; the SSH escape sequence does.**

The reset takes longer this time (5–10 min in some cases). If SSH refuses to reconnect after that wait, fall back to the Azure portal Serial console (`vm-ftdv > Help > Serial console`) — it works even when the management plane is wedged.

Verify the change applied with `show network`:

```
IPv4 Default route Gateway : data-interfaces        ← what you want
Ethernet0/1                : Manual / 10.100.2.10
```

## 6. Re-issue the registration token in SCC, then register

This step is **not** what the Cisco docs imply. Day-0 JSON pre-seeded a registration attempt at first boot (using the values from `terraform.tfvars`), but that attempt failed because management had no Internet egress at that moment, and SCC marked the reg key as consumed. Reusing the same values via `configure manager add` will not work.

**On SCC:**

1. cdFMC > Inventory > Devices > select the pending FTDv record.
2. Click **Re-issue Registration Token** (wording varies by SCC release — also seen as "Reset registration token", "Generate new token", or similar). Confirm.
3. SCC produces a new `configure manager add ...` command with a fresh reg key and NAT ID. Copy the full line.

**On FTD:**

```
> configure manager delete
> configure manager add <new-fqdn> <new-reg-key> <new-nat-id> <new-display-name>
```

Paste the entire SCC-provided line into the second command. SCC includes the display name as the 4th argument; keep it — that's what shows up in cdFMC's inventory.

## Verify

`show managers` on FTD progresses `Pending → Completed` within 3–5 minutes (sometimes up to 10 min on first registration). In parallel, SCC's inventory page animates `Pending → Synchronizing → Healthy`.

When `Registration: Completed` shows up:

```
> show version
```

Expected: an FTD version string starting with `10.` (the workshop deploys 10.x).

```
> show interface ip brief
```

Expected: `Ethernet0/1` (outside) shows `10.100.2.10/24` and is `up/up`. Inside (`Ethernet0/2`) shows `10.100.3.10/24` and may still be `administratively down` until cdFMC pushes interface policy in the next phase.

## When it gets stuck

- **Stuck at Pending after re-issued token:** more than 10 min after `configure manager add` with a fresh token, registration is not progressing. Check that `nsg-outside` still permits TCP 8305 outbound (`Allow-Sftunnel-Outbound`), and that the FTD's clock is reasonably accurate (off by hours = TLS handshake fails). FMC-managed FTDs delegate NTP to FMC, so you cannot fix clock skew at the FTD CLI directly — that's a deeper troubleshoot.
- **`configure network management-data-interface` rejects with "not supported when Management interface is not configured to use a static address":** you skipped step 4. Convert management to manual first, then retry.
- **Bastion connection times out:** the FTDv is still booting. Wait five more minutes and try again. If it has been 30 minutes since `terraform apply` and SSH still times out, fall back to the Azure portal Serial console — it works regardless of management plane state.
- **The first `configure manager add` you typed (with values from `terraform.tfvars`) keeps showing Pending:** that's not a typo issue; it's the consumed-token issue. Re-issue the token in SCC and re-add. See the FTDv "don't pre-seed cdFMC registration" entry in `LESSONS-LEARNED.md` for the full story.
