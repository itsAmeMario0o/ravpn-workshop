# ISE deploy via Azure Portal

This guide walks through deploying Cisco ISE on Azure using the Azure Portal Marketplace flow. We do this manually instead of with Terraform because the Marketplace ISE images (3.3, 3.4, 3.5) all fail Terraform's `apply` step with `OSProvisioningTimedOut` at the 20-minute mark. The Portal flow handles the same timeout differently and gets the VM up. See `LESSONS-LEARNED.md` for the full story.

End state of this step:

- One ISE VM running in `rg-ravpn-demo`, named `vm-ise`, with private IP `10.100.4.10` on the identity subnet.
- ISE first boot completes in another 45-60 minutes after the Portal returns. The ISE GUI is reachable through Bastion at `https://10.100.4.10` after that wait.
- `keys/ise_admin` and `keys/ise_admin.pub` exist locally for SSH access to the underlying Linux `iseadmin` user. The ISE GUI on port 443 still uses the password you set in the Portal flow.

Plan ~10 minutes of click-through, then 45-60 minutes of waiting for ISE to finish first boot.

## Before you start

Everything else in the build must already be deployed via Terraform. Specifically these resources must exist in `rg-ravpn-demo`:

| Resource | Purpose |
|---|---|
| `vnet-demo` | The VNet the VM attaches to |
| `snet-identity` | The subnet ISE lives on (10.100.4.0/24) |
| FTDv, app VM, Bastion | Don't matter for this step, but they should be up |

Verify:

```bash
az resource list -g rg-ravpn-demo --query "[?type=='Microsoft.Network/virtualNetworks'].name" -o tsv
az network vnet subnet show -g rg-ravpn-demo --vnet-name vnet-demo --name snet-identity --query "{name:name, prefix:addressPrefix}"
```

Both commands should succeed.

The ISE module in `infra/main.tf` is commented out, and there is no resource at IP `10.100.4.10` yet. Confirm:

```bash
az vm list -g rg-ravpn-demo --query "[].name" -o tsv
```

`vm-ise` should not be in the list. If it is, delete the leftover with `az vm delete -g rg-ravpn-demo -n vm-ise --yes` and remove its OS disk.

You also need an SSH keypair on your laptop. We generate one fresh:

```bash
mkdir -p keys
ssh-keygen -t rsa -b 4096 -f keys/ise_admin -N "" -C "iseadmin@ise-ravpn"
chmod 600 keys/ise_admin
chmod 644 keys/ise_admin.pub
cat keys/ise_admin.pub
```

The public key prints to your terminal. You will paste it into the Portal in step 4. The `keys/` directory is gitignored, so the private key stays on your laptop.

You also need the ISE admin password from your password manager. This is the same password you set as `ise_admin_password` in `terraform.tfvars`. ISE's GUI and CLI use it.

## Step 1 — Open the Marketplace listing

1. Sign in to the Azure Portal: `https://portal.azure.com`.
2. In the search bar at the top, type `Cisco Identity Services Engine` and select the result published by Cisco.
3. On the product page, **do not click the blue "Create" button yet**. First, change the plan.
4. Above the "Create" button there is a **Plan** dropdown. Open it. You will see four options: `cisco-ise_3_2`, `cisco-ise_3_3`, `cisco-ise_3_4`, `cisco-ise_3_5`.
5. Select **`cisco-ise_3_3`**.

Why 3.3: Cisco TAC case notes report 3.4 has unresolved provisioning bugs on Azure even outside our specific Terraform issue. 3.3 is the most recent version documented as stable. ISE 3.3 covers everything this workshop needs (REST ID against Entra, RADIUS to FTDv, basic GUI).

6. Click **Create**.

## Step 2 — Basics tab

The Portal opens a multi-tab form. The Basics tab fills in subscription, resource group, region, and the VM identity.

| Field | Value |
|---|---|
| Subscription | The same subscription Terraform is using. Use `az account show --query name` to confirm. |
| Resource group | `rg-ravpn-demo` (existing — do not create a new one) |
| Virtual machine name | `vm-ise` |
| Region | `(US) East US 2` (eastus2 — same region as everything else) |
| Availability options | `No infrastructure redundancy required` |
| Security type | `Standard` |
| Image | Should already say `Cisco Identity Services Engine (ISE) - cisco-ise_3_3`. If it says a different SKU, go back and re-pick the plan. |
| VM architecture | `x64` |
| Size | Click "See all sizes" → search for **`Standard_D8s_v4`** → select it |

The size is the one Cisco supports for an Extra Small PSN-only ISE deployment. 8 vCPU, 32 GB RAM. Smaller sizes will be rejected by ISE during first boot.

| Field | Value |
|---|---|
| Authentication type | **`SSH public key`** |
| Username | `iseadmin` |
| SSH public key source | `Use existing public key` |
| SSH public key | Paste the **entire** contents of `keys/ise_admin.pub` (output of `cat keys/ise_admin.pub` from the prerequisites). It begins with `ssh-rsa AAAA…` and ends with `iseadmin@ise-ravpn`. |
| Public inbound ports | **`None`** |

Public inbound ports `None` is correct because ISE is reached through Bastion, not directly from the Internet.

Click **Next: Disks**.

## Step 3 — Disks tab

| Field | Value |
|---|---|
| OS disk type | `Premium SSD (locally-redundant storage)` |
| OS disk size | **`300 GiB`** (click "Customize" if the default is smaller) |
| Delete OS disk with VM | Checked |
| Encryption type | `(Default) Encryption at-rest with a platform-managed key` |
| Enable Ultra Disk compatibility | Unchecked |

300 GB is a Cisco minimum. Smaller disks fail ISE first boot partway through.

Click **Next: Networking**.

## Step 4 — Networking tab

| Field | Value |
|---|---|
| Virtual network | **`vnet-demo`** (existing — pick from dropdown, do not create new) |
| Subnet | **`snet-identity (10.100.4.0/24)`** |
| Public IP | **`None`** (click the dropdown and explicitly choose None) |
| NIC network security group | **`None`** (the subnet already has the right NSGs from Terraform) |
| Delete public IP and NIC when VM is deleted | Checked |
| Accelerated networking | `Disabled` (ISE does not benefit; Cisco does not require it) |
| Place this virtual machine behind an existing load balancing solution? | Unchecked |

Specifically check the Public IP field. Azure's default is to create one. We do not want that — ISE has no reason to be on the public Internet.

The NIC will be auto-named `vm-iseVMNic` or similar. We will rename it later if needed.

Click **Next: Management**.

## Step 5 — Management tab

| Field | Value |
|---|---|
| Microsoft Defender for Cloud | Either Basic or Standard — does not matter for this demo |
| Enable system assigned managed identity | Unchecked |
| Enable auto-shutdown | Unchecked |
| Boot diagnostics | `Enable with managed storage account (recommended)` |
| Enable OS guest diagnostics | Unchecked |
| Patch orchestration options | `Image default` |

Boot diagnostics on is useful so you can read the serial console if ISE first boot misbehaves. Everything else is off because this is a demo VM that runs for hours, not days.

Click **Next: Advanced**.

## Step 6 — Advanced tab (the user_data field)

This is the critical step. ISE reads its bootstrap configuration from the `user_data` field. Wrong content here means ISE either fails to boot or boots with wrong NTP, DNS, or admin credentials.

Scroll down to the **User data** section.

1. Check the box **"Enable user data"**.
2. In the User data text area, paste **exactly** this content. **Replace `REPLACE_WITH_ISE_ADMIN_PASSWORD` with the same admin password you set in `terraform.tfvars` for `ise_admin_password`.**

```
hostname=ise-ravpn
primarynameserver=168.63.129.16
dnsdomain=ravpn.local
ntpserver=time.windows.com
timezone=UTC
password=REPLACE_WITH_ISE_ADMIN_PASSWORD
ersapi=yes
openapi=yes
pxGrid=yes
pxgrid_cloud=yes
```

Field-by-field:

| Field | Value | Why |
|---|---|---|
| `hostname` | `ise-ravpn` | The hostname ISE registers internally and on its self-signed cert |
| `primarynameserver` | `168.63.129.16` | Azure's internal DNS resolver, reachable from any subnet without extra config |
| `dnsdomain` | `ravpn.local` | The DNS domain ISE appends when it resolves short names. Internal-only, not a real domain |
| `ntpserver` | `time.windows.com` | Public NTP. ISE 3.3 uses the field name `ntpserver=`. **If you ever switch to 3.4 or 3.5, change this line to `primaryntpserver=` — the field was renamed in 3.4.** |
| `timezone` | `UTC` | Match the rest of the build |
| `password` | The admin password | Sets the iseadmin account password for the GUI on 443 and the ISE-style CLI on 22 |
| `ersapi`, `openapi`, `pxGrid`, `pxgrid_cloud` | All `yes` | Turn on ISE's APIs so we can configure ISE programmatically later |

Make sure there are no extra spaces, no trailing whitespace, no blank lines at the end. The Portal sends the field as-is.

3. Leave **Custom data** empty. This is a different field that ISE does not read.

Click **Next: Tags**.

## Step 7 — Tags tab

Add the same three tags Terraform applies to everything else, so cost reports filter cleanly:

| Name | Value |
|---|---|
| `project` | `ravpn-demo` |
| `environment` | `demo` |
| `owner` | `mario` |

Apply them to all resources the form will create (VM, NIC, OS disk, etc.).

Click **Next: Review + create**.

## Step 8 — Review and create

The Portal validates the form. You should see a green "Validation passed" banner.

Below it, the Portal shows pricing and the Cisco marketplace terms. Marketplace terms for `cisco-ise_3_3` were accepted earlier (`az vm image terms accept --publisher cisco --offer cisco-ise-virtual --plan cisco-ise_3_3` returned `True`). The terms screen should let you proceed without re-accepting.

Confirm:

- **VM size**: `Standard_D8s_v4` (8 vCPUs, 32 GiB RAM)
- **Image**: `Cisco Identity Services Engine (ISE) - cisco-ise_3_3`
- **Region**: East US 2
- **Resource group**: rg-ravpn-demo
- **Disk**: 300 GiB Premium SSD
- **Public IP**: None

If anything is wrong, click Previous and fix it. If everything looks right, click **Create**.

## Step 9 — Wait

The Portal shows a deployment progress page. Three things will happen:

1. **0-5 minutes:** Azure creates the disk, NIC, and VM resources. The progress bar fills.
2. **5-20 minutes:** Azure waits for the in-guest agent to report "OS provisioning complete." ISE is busy installing in the background, but the agent does not finish before Azure's timeout.
3. **At 20 minutes:** Azure may show a deployment **"Failed"** banner with `OSProvisioningTimedOut`. **This is expected.** The error message itself says: "The VM may still finish provisioning successfully. Please check provisioning state later."

If you see the Failed banner, **do not delete the VM**. Click **"Go to resource"** instead. The VM page will show the VM as `Provisioning state: Failed` but `Status: Running`. ISE is still booting underneath.

Now wait another 30-45 minutes. ISE will finish first boot. The Provisioning state will eventually flip to `Succeeded` on its own. You can refresh the Overview tab every 5 minutes to check.

Total wall-clock time from "click Create" to "ISE GUI responds": 60-90 minutes.

## Step 10 — Verify

When the Provisioning state shows `Succeeded`:

```bash
# Confirm VM is running and provisioning succeeded
az vm show -g rg-ravpn-demo -n vm-ise --query "{state:provisioningState, power:instanceView.statuses[?starts_with(code, 'PowerState')].displayStatus | [0]}" -o table

# Confirm the private IP landed on the right address
az vm list-ip-addresses -g rg-ravpn-demo -n vm-ise --query "[].virtualMachine.network.privateIpAddresses[]" -o tsv
```

Expected:

- `state` = `Succeeded`, `power` = `VM running`.
- Private IP = `10.100.4.10`. If it's something else (say `10.100.4.4`), the rest of the build still works but you will need to update Cloudflare DNS targets and ISE config files to match.

Now confirm the ISE GUI is up. Open a Bastion tunnel:

```bash
ISE_PORT=443 scripts/bastion-tunnel.sh ise 50443
```

Leave the tunnel running. In a browser:

```
https://127.0.0.1:50443
```

Accept the self-signed cert warning. Sign in as `iseadmin` with the password you set in `user_data`.

If the GUI returns "connection refused" or "page not loading," wait another 5-10 minutes — ISE services finish starting up after the Provisioning state flips. The CLI is reachable on port 22 of the same private IP, but again only through Bastion.

## Step 11 — Continue with the build

Once ISE is up, return to the regular build sequence:

- `setup/ise-config.md` — configure REST ID, NAD, and policy sets
- `setup/cdFMC-registration.md` — if not already done

The rest of the build assumes ISE responds at `10.100.4.10` on the identity subnet, which it does.

## Optional: import the Portal-deployed VM into Terraform

Once everything is confirmed working, you can re-attach the VM to Terraform state so the rest of the build is back under one tool. This is optional and not required for the demo.

1. Uncomment the `module "ise"` block in `infra/main.tf`.
2. Uncomment the `ise_private_ip` and `ise_ssh_key_path` outputs in `infra/outputs.tf`.
3. Pin the ISE module variables to match what the Portal deployed:
   - `ise_image_plan` should already default to `cisco-ise_3_3` in `infra/variables.tf`.
   - The user_data block in `infra/modules/ise/main.tf` already uses `ntpserver=` (3.3 syntax). It matches what you pasted in the Portal.
4. Run `terraform plan`. Terraform will show it wants to create everything — that is wrong. We need to import first.
5. Get the VM's resource ID:
   ```bash
   az vm show -g rg-ravpn-demo -n vm-ise --query id -o tsv
   ```
6. Import:
   ```bash
   terraform import module.ise.azurerm_linux_virtual_machine.this <vm-id-from-step-5>
   ```
7. Re-run `terraform plan`. There will likely be diffs (the Portal-set NIC name, tags, agent flags). Adjust the module to match the Portal-deployed reality, or accept the diff and let Terraform reconcile on the next apply.

If the diff is messy, leave the module commented out and treat ISE as unmanaged for this demo. The workshop runs fine either way.

## Things that go wrong

| Symptom | Likely cause | Fix |
|---|---|---|
| Portal shows `OSProvisioningTimedOut` and the VM never flips to Succeeded | The VM agent never came up. ISE may have hit a bootstrap error in user_data. | Check the user_data field again. Common errors: trailing whitespace, wrong field names, password with characters the Portal didn't preserve. |
| ISE GUI returns 404 or wrong cert hostname | First boot still in progress | Wait another 15 minutes. ISE generates its self-signed cert near the end of first boot. |
| ISE CLI accepts password but rejects SSH key | Username typo or wrong key file | Confirm `iseadmin` (lowercase) and the matching `keys/ise_admin` (private key). The public key you pasted must be the full single-line `ssh-rsa AAAA… iseadmin@ise-ravpn`. |
| ISE got a different IP than 10.100.4.10 | Azure picked a free IP from the subnet, not the static one we wanted | Either accept the new IP and update DNS/ISE config, or delete the VM and redeploy with **Static** IP allocation in the Networking tab. The Portal has a "Private IP address allocation" radio that defaults to Dynamic. |
