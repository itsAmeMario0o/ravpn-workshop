# Terraform deploy

This is the step where Azure resources actually get created. Up until now the build has been local config (DNS, Entra, certs, SCC pending records). Once you run `terraform apply` here, real VMs spin up and the meter starts.

End state of this step:

- Resource group `rg-ravpn-demo` exists in your Azure subscription, region `eastus2`.
- VNet, subnets, NSGs, public IPs, three VMs (FTDv, ISE, trading app), and Bastion all running.
- An SSH keypair for the trading app VM has been generated locally at `keys/ravpn_workshop`.
- Terraform outputs tell you the FTDv outside public IP so you can update Cloudflare.

Plan ~15-20 minutes from `apply` start to all resources reaching `Succeeded`. ISE is the slow one — its VM provisions quickly, but the ISE software needs another 45-60 minutes to finish first boot before the GUI responds.

## Prerequisites

Phase 1 must be done. Specifically:

- DNS records exist in Cloudflare ([dns-config.md](dns-config.md)).
- Both certs generated locally ([tls-certs.md](tls-certs.md)).
- Entra ID config done and ROPC verified ([entra-config.md](entra-config.md)).
- SCC pending device record exists with all four licenses claimed including Cisco Secure Client Premier ([scc-onboarding.md](scc-onboarding.md)).
- You have the reg key, NAT ID, and the full `configure manager add ...` command saved in your password manager.

If any of those is missing, do not proceed. Terraform will provision the resources fine, but the FTDv won't be able to register with cdFMC, the cert work will be incomplete, and you'll spend hours debugging cascading issues.

## Step 1 — Fill in `terraform.tfvars`

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` is gitignored — anything you put in it stays local. The `.example` template stays in the repo as documentation.

Open `terraform.tfvars` in your editor and fill in **only the four sensitive values**. Everything else has a sensible default that you should leave alone unless you know why you're changing it.

```hcl
ftdv_admin_password = "<your FTDv admin password>"
ftdv_reg_key        = "<reg key from SCC>"
ftdv_nat_id         = "<NAT ID from SCC>"
ise_admin_password  = "<your ISE admin password>"
```

### Parsing the SCC `configure manager add` command

SCC gave you a single line that looks like:

```
configure manager add <fmc-host> <reg-key> <nat-id> <display-name>
```

The position is fixed across Cisco versions:

| Position | Field | tfvars variable |
|---|---|---|
| 2nd word | reg key | `ftdv_reg_key` |
| 3rd word | NAT ID | `ftdv_nat_id` |

The 1st word (the SCC FQDN) and 4th word (display name) don't go in tfvars. The full command itself goes into the FTD CLI later, in [cdFMC-registration.md](cdFMC-registration.md).

### Password complexity

Both FTDv and ISE enforce password complexity. Practical minimum that satisfies both:

- 8-30 characters
- At least one uppercase, one lowercase, one digit, one special character

Save whatever you set in your password manager — these are admin passwords for production-grade security products.

### Quoting

HCL uses **double quotes** for strings. Unlike zsh, HCL has no history expansion, so a `!` in a password is fine inside `"..."`. If your editor sneaks in curly quotes (`"` `"` instead of `"`), Terraform will fail with a parse error. Stick with straight ASCII quotes.

## Step 2 — Verify the file is gitignored

```bash
cd ..  # back to repo root
git status
```

You should **not** see `infra/terraform.tfvars` in the output. If you do, stop and check `.gitignore` — the rule `*.tfvars` (with `!terraform.tfvars.example` as the exception) is what protects it.

## Step 3 — Initialize Terraform

```bash
cd infra
terraform init
```

This downloads provider plugins (`azurerm`, `random`, `tls`, `local`) into `.terraform/`. The first run takes a minute or two depending on network speed.

**Expected:** the output ends with `Terraform has been successfully initialized!`. If init fails, the error usually points at a network issue (corporate proxy, missing CA cert) or a provider version conflict.

## Step 4 — Dry run with `plan`

```bash
terraform plan
```

This evaluates every resource against your tfvars and tells you exactly what it would do — without touching Azure yet. **Always run plan before apply.**

**Expected:** the last line of the output is:

```
Plan: NN to add, 0 to change, 0 to destroy.
```

`NN` is typically in the 25-35 range. The exact count depends on provider version. What matters:

- The `to add` number is non-zero (creating from scratch).
- The `to change` and `to destroy` numbers are zero on a first run.
- No errors above the summary.

Spot-check a few resources in the output:

- `azurerm_resource_group.this` → name `rg-ravpn-demo`, location `eastus2`.
- FTDv VM → `size = "Standard_D4s_v3"` (matches FTDv5 tier sizing).
- ISE VM → `size = "Standard_D8s_v4"` (Cisco's smallest supported Azure size).
- `tls_private_key.this` (in module.app) → `algorithm = "ED25519"`.
- The Day-0 JSON for FTDv shows `(sensitive value)` for `custom_data`. That's correct — Terraform redacts sensitive content in plan output.

### Common plan errors

| Error | Fix |
|---|---|
| `Insufficient privileges to complete the operation` | Re-run `az login`. Confirm `az account show` shows the right subscription. |
| `marketplace purchase eligibility check returned errors` | Re-run `az vm image terms accept` for the SKU named in the error. Run `scripts/preflight.sh` to confirm both FTDv and ISE marketplace terms are accepted. |
| `Error: Unsupported argument` | HCL parse error in `terraform.tfvars` — most often curly quotes pasted from a doc. |
| `Error: required field is not set` | A required variable (no default) is missing from `terraform.tfvars`. Check the four required values are all there. |

## Step 5 — Apply

When `plan` looks good:

```bash
terraform apply
```

Terraform shows the plan again and asks you to type `yes` to proceed. Type `yes` and let it run.

**Timing:**

- First few minutes: resource group, VNet, subnets, NSGs, public IPs, network interfaces — fast.
- Next 5-10 minutes: Bastion, the three VMs. Bastion is the slowest of the three because it's a managed PaaS resource.
- Apply returns control when the Azure-side provisioning is `Succeeded`. **The VMs are running, but the software inside them is still booting.** FTDv needs another 15-20 minutes; ISE needs 45-60 minutes.

If apply errors mid-run, re-running `terraform apply` is safe — Terraform picks up where it left off. Don't worry about partial state.

## Step 6 — Read the outputs

```bash
terraform output
```

You'll see:

```
app_private_ip          = "10.100.3.20"
app_ssh_key_path        = "infra/../keys/ravpn_workshop"
bastion_name            = "bastion-demo"
ftdv_mgmt_private_ip    = "10.100.0.10"
ftdv_outside_public_ip  = "<the new public IP>"
ise_private_ip          = "10.100.4.10"
resource_group_name     = "rg-ravpn-demo"
```

The `ftdv_outside_public_ip` is what you need for the next step. Pull it as raw value:

```bash
terraform output -raw ftdv_outside_public_ip
```

## Step 7 — Update Cloudflare A records

Back in the Cloudflare dashboard for `rooez.com`:

1. **DNS > Records**.
2. Edit each of `vpn`, `trading`, and `ise`.
3. Replace the placeholder `1.1.1.1` with the value of `ftdv_outside_public_ip`.
4. Confirm the cloud icon stays gray (DNS only).
5. Save.

### Verify

```bash
for r in vpn trading ise; do
  printf "%-20s %s\n" "${r}.rooez.com" "$(dig +short ${r}.rooez.com)"
done
```

All three should now return the FTDv outside IP.

## Step 8 — Run smoke test

```bash
cd ..
scripts/smoke-test.sh
```

This script reads the Terraform outputs and walks the verification checklist: resource group exists, all three VMs running, DNS resolves to the right IP, FTDv outside reachable on TCP 443, cert SANs match. Should print a row of green `[OK]` lines and `summary: 6 OK, 0 FAIL` (or similar).

If the cert SAN check fails at this stage, it's because no cert is bound to FTDv yet — that happens in [cdFMC-registration.md](cdFMC-registration.md) and Phase 5. Ignore it for now if every other check is green.

## What to do if something breaks

| Symptom | Likely cause | Fix |
|---|---|---|
| `terraform apply` times out on a VM | Region capacity or quota issue | Re-run apply; if it persists, check quota with `scripts/preflight.sh` |
| All VMs created but FTDv won't accept SSH via Bastion | FTD bootstrap still in progress | Wait 15-20 minutes after VM reaches running, then retry |
| ISE GUI returns `connection refused` | ISE first boot still in progress | Wait 45-60 minutes after VM reaches running |
| Output shows the right resources but nothing in Azure portal | Wrong subscription active | `az account show` and confirm; if wrong, `az account set ...` then `terraform refresh` |

## Tear-down

When the workshop ends:

```bash
cd infra
terraform destroy
```

Type `yes` to confirm. Destroy takes about as long as apply. After it finishes, also:

- Remove the FTDv from the cdFMC inventory (if registration completed).
- Drop the Cloudflare A records for `vpn`, `trading`, `ise` (or set them back to placeholder).
- Revoke the Let's Encrypt cert if you don't plan to reuse it.

The `keys/` and `certs/` directories on your laptop are not affected by destroy — they're local files. Delete them manually if you want a clean slate, or leave them for the next run.
