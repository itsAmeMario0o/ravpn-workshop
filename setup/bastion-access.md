# Bastion access

How to reach the firewall, ISE, and the trading app VM through Azure Bastion. None of those VMs has a public IP. Bastion is the only path in.

## What Bastion actually is

Azure Bastion is a managed jumphost. Our three VMs (FTDv, ISE, trading app) sit on private subnets with no public IP. Bastion lives in `AzureBastionSubnet` with its own public IP and acts as a TLS proxy. Your laptop talks to Bastion over HTTPS; Bastion talks to the target VM's private IP. The VM's IP is never exposed to the public internet.

There are two ways to use Bastion: a **CLI tunnel** (what `scripts/bastion-tunnel.sh` does) and a **browser session** (Portal click-through). Both work. The CLI tunnel is the workhorse for this build because it lets you point any client (ssh, browser, curl) at the VM. The browser session is a quick visual-only fallback.

## Method 1 — CLI tunnel (the script)

The helper at `scripts/bastion-tunnel.sh` runs:

```
az network bastion tunnel \
  --name bastion-demo \
  --resource-group rg-ravpn-demo \
  --target-resource-id <VM-resource-id> \
  --resource-port <port-on-the-VM> \
  --port <port-on-your-laptop>
```

That opens a TCP forward: `127.0.0.1:<local-port>` on your laptop → Bastion → target VM's `<resource-port>`.

The script stays in the foreground. Open a second terminal or browser tab to actually use the connection. **Ctrl+C closes the tunnel.**

Three usage patterns cover everything in this build.

### ISE — GUI on 443, CLI on 22

```bash
# Terminal 1: open the GUI tunnel
ISE_PORT=443 scripts/bastion-tunnel.sh ise 50443
```

```bash
# Browser
open https://127.0.0.1:50443
```

Sign in as `iseadmin` with the password from `terraform.tfvars` (`ise_admin_password`). Most ISE configuration happens in the GUI.

When you need a shell to verify services or pull logs:

```bash
# Terminal 2: CLI tunnel
scripts/bastion-tunnel.sh ise 50022
```

```bash
# Terminal 3: SSH to ISE
ssh -i keys/ise_admin -p 50022 iseadmin@127.0.0.1
```

You land at the ISE-style CLI (`ise-ravpn/iseadmin#`). The most useful command is `show application status ise` — every service should say `running` once first boot finishes.

### FTDv — CLI on 22

The FTDv has no GUI. All FTD configuration goes through cdFMC. The only reason to SSH directly is the initial registration step.

```bash
# Terminal 1
scripts/bastion-tunnel.sh ftdv 50022
```

```bash
# Terminal 2
ssh -p 50022 admin@127.0.0.1
```

You'll be prompted for the FTDv admin password (`ftdv_admin_password` in `terraform.tfvars`). You land at the FTD CLI prompt (`>`). This is where you paste the `configure manager add ...` command from SCC, covered in `cdFMC-registration.md`.

Use `admin`, not `cisco`. Our Terraform module sets the Azure-side `admin_username` to `cisco` because Azure reserves the literal username `admin` for VM creation. SSH as `cisco` lands at the FX-OS Linux shell, where FTD commands do not exist and sudoers will not let you switch to `admin`. SSH as `admin` (the FTD-internal user, configured by Day-0 JSON's `AdminPassword`) lands at the FTD CLI directly. See the FTDv entry in `LESSONS-LEARNED.md` for the full story.

### Trading app VM — SSH on 22

Useful for nginx logs, cert troubleshooting, and the deploy script.

```bash
# Terminal 1
scripts/bastion-tunnel.sh app 50022
```

```bash
# Terminal 2
ssh -i keys/ravpn_workshop -p 50022 appadmin@127.0.0.1
```

## Method 2 — Browser session (Portal click-through)

When you just want a one-off look at a VM:

1. Azure Portal → search for the VM (`vm-ise`, `vm-ftdv`, or `vm-tradingapp`) → open it.
2. Left-hand menu → **Connect** → **Bastion**.
3. Authentication type: **SSH Private Key from Local File** for ISE and the app; **Password** for FTDv.
4. Username: `iseadmin` for ISE, `cisco` for FTDv, `appadmin` for the trading app.
5. Upload the matching key file (`keys/ise_admin` or `keys/ravpn_workshop`) or type the FTDv password.
6. Click **Connect**.

A browser tab opens with a terminal session straight to the VM. Close the tab to disconnect.

The browser session is shell-only. To reach ISE's web GUI, you still need the Method 1 CLI tunnel — there is no browser equivalent for HTTPS-to-VM.

## Quick reference

| Goal | Local port | Tunnel (Terminal 1) | Connection (Terminal 2 / browser) |
|---|---|---|---|
| ISE GUI | 50443 | `ISE_PORT=443 scripts/bastion-tunnel.sh ise 50443` | `open https://127.0.0.1:50443` |
| ISE CLI | 50022 | `scripts/bastion-tunnel.sh ise 50022` | `ssh -i keys/ise_admin -p 50022 iseadmin@127.0.0.1` |
| FTDv CLI | 50022 | `scripts/bastion-tunnel.sh ftdv 50022` | `ssh -p 50022 admin@127.0.0.1` (password) |
| Trading app | 50022 | `scripts/bastion-tunnel.sh app 50022` | `ssh -i keys/ravpn_workshop -p 50022 appadmin@127.0.0.1` |

## Things that go wrong

- **One tunnel per terminal.** Each `bastion-tunnel.sh` invocation occupies a terminal. Open a new terminal window or tab for each tunnel you need at the same time.
- **Local port reuse.** If you stop a tunnel and immediately try to start another on the same local port you may get "address already in use." Wait about 30 seconds for the OS to release the socket, or pick a different local port (50023, 51022, etc.).
- **First connect feels slow.** Bastion takes a few seconds to set up the first TCP session per tunnel. After that it's fast.
- **Bastion costs the same whether you use it or not.** Our `bastion-demo` is Standard SKU, billed by the hour as long as it exists. Leaving tunnels open does not cost extra; the Bastion service itself is the line item. Tear it down with `terraform destroy` when the workshop ends.
- **The browser session asks for both username and key.** Some Portal versions show a separate "Username" field even when you upload an SSH key. Fill both in. The key file alone is not enough.
