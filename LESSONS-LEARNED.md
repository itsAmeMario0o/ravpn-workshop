# Lessons learned

Things we hit during the build that aren't obvious from a clean pull of the repo. If something fails in a way that leaves you searching, the fix is probably here.

Each entry has three parts:

- **Symptom** — what you'll see when you hit this.
- **Cause** — why it happens.
- **Fix** — what we did about it.

---

## Cloud and Azure

### Regional vCPU cap blocks deploy even when family quotas look fine

**Symptom:** `terraform apply` fails partway through with a quota error mentioning "regional cores," even though the per-family quotas (DSv3, DSv4, BS) look like they have plenty of headroom.

**Cause:** Azure has two layers of quota in the same region. Per-family caps say "you can have N vCPUs of this VM family." A separate **Total Regional vCPUs** cap says "across every family combined, no more than N vCPUs." The default for a new subscription is 10. This demo needs 17 (FTDv 8 on D8s_v3 + ISE 8 on D8s_v4 + app 1 on B1s).

**Fix:** Request a quota increase via the Azure portal (Subscriptions > your subscription > Usage + quotas > filter to your region > "Total Regional vCPUs"). Ask for at least 24 to give yourself headroom. Approval is usually quick on default-tier subscriptions.

`scripts/preflight.sh` checks this before every deploy.

### Marketplace terms are per-SKU, not per-publisher

**Symptom:** Terraform fails to deploy a VM with "marketplace terms not accepted" even though you accepted terms for what you thought was the same image earlier.

**Cause:** Cisco publishes FTDv under multiple marketplace SKU names: the legacy `ftdv-azure-byol`/`ftdv-azure-payg` (for FTD 7.x and earlier) and the newer `cisco-ftdv-x86-byol`/`cisco-ftdv-x86-payg` (for FTD 10.x). Accepting terms for one does not carry over to the other. Same publisher, same offer name, different SKU.

**Fix:** Run `az vm image terms accept` for the exact plan name in `infra/variables.tf`. Today that's `cisco-ftdv-x86-byol` for FTDv and `cisco-ise_3_5` for ISE. If you switch the SKU, accept the new terms before re-running apply.

### Azure VM size dictates max NIC count, not just vCPU/RAM

**Symptom:** `terraform apply` fails creating the FTDv VM with `NetworkInterfaceCountExceeded: The number of network interfaces is 4 and the maximum allowed is 2`.

**Cause:** Azure caps the number of NICs you can attach based on the VM **size**, not the family. FTDv needs four NICs (mgmt, diagnostic, outside, inside) regardless of license tier. In the Dsv3 family, NIC limits are: D2s_v3 = 2, D4s_v3 = 2, D8s_v3 = 4, D16s_v3 = 8. In the Fsv2 family: F2s_v2 = 2, F4s_v2 = 2, F8s_v2 = 4, F16s_v2 = 8. Cisco's FTDv tier sizing tables only mention vCPU and RAM, so it's easy to "right-size" to FTDv5's 4 vCPU recommendation and end up with a VM size that won't take the four NICs.

**Fix:** Use Standard_D8s_v3 (smallest Dsv3 size supporting 4 NICs) or Standard_F8s_v2 (smallest Fsv2 size supporting 4 NICs) for FTDv on Azure, regardless of the FTDv performance tier license you've claimed. The "extra" CPU/RAM is wasted on the FTDv5 license tier but Azure forces the size.

### "admin" is a reserved username on Azure VMs

**Symptom:** `terraform validate` succeeds, but `terraform apply` fails immediately with a long error listing reserved usernames including "admin", "administrator", "user", and a few dozen others.

**Cause:** Azure refuses to provision a VM with `admin_username` set to common values that attackers spray.

**Fix:** Pick something else. The FTDv module uses `cisco` as the Azure-side admin username. The actual FTD admin login (the one you SSH in with) is set by the Day-0 JSON's `AdminPassword` field, which is unrelated to Azure's `admin_username`.

### ISE on Azure: portal-deploy workaround (Terraform path is broken)

**Symptom:** `terraform apply` for the ISE VM fails after exactly 20 minutes with `OSProvisioningTimedOut: OS Provisioning for VM 'vm-ise' did not finish in the allotted time`. This happens on every Cisco ISE marketplace image we tried (3.3, 3.4, 3.5), with every Terraform configuration we tried.

**Cause:** Azure considers a Linux VM "Succeeded" only after an in-guest provisioning agent (cloud-init / AzureInit / WALA) sends a ready signal back to the platform. Azure waits about 20 minutes for that signal, then marks the resource Failed. The Cisco ISE Azure marketplace image does not ship a cooperating agent in a state Azure recognizes within that window. ISE's own first boot takes 45-60 minutes and the agent never makes it out of bootstrap before Azure gives up.

Microsoft's marketplace VM FAQ acknowledges this trade-off: "Publishing without an agent may show 'Provisioning failed' in the portal even if the VM runs successfully." Cisco published their ISE image under that trade-off.

**What we tried and observed (five `terraform apply` runs):**

| Attempt | ISE version | Bootstrap | Auth | VM agent | Outcome |
|---:|---|---|---|---|---|
| 1 | 3.5 | `user_data` | password | default (true) | OSProvisioningTimedOut at 20m |
| 2 | 3.5 | `user_data` | SSH key (RSA 4096) | default (true) | OSProvisioningTimedOut at 20m |
| 3 | 3.5 | `user_data` | SSH key | `provision_vm_agent = false` | OSProvisioningTimedOut at 20m |
| 4 | 3.4 | `user_data` | SSH key | default (true) | OSProvisioningTimedOut at 20m |
| 5 | 3.3 | `user_data` | SSH key | default (true) | OSProvisioningTimedOut at 20m |

The pattern is identical across versions and configurations. This is not an ISE-version problem and not an auth-mode problem. Azure's platform timeout fires before the marketplace image's in-guest agent reports ready.

**Cisco TAC case-note input:**

A Cisco TAC case from another customer surfaced two related items:

- ISE 3.4+ requires `primaryntpserver=` in `user_data`, not the older `ntpserver=`. ISE 3.3 still uses `ntpserver=`. Wrong field name silently fails to parse and leaves NTP unconfigured. This was a bug in our code (now corrected), but it was not the root cause of the deploy timeout.
- The same customer concluded ISE 3.4 on Azure was not stable enough for production and rolled back to ISE 3.3. We saw the same OSProvisioningTimedOut behavior on 3.3 in our environment, so the version downgrade alone does not solve it for Terraform.

**Workaround in this build: deploy ISE through the Azure Portal, then import.**

The Azure Portal's marketplace deployment path appears to handle the OS-provisioning timeout differently. It either uses `--no-wait` semantics behind the scenes or simply tolerates the platform marking the VM Failed during the first boot window. Either way, deploying through the Portal is the documented workaround when the marketplace image's agent timing does not match the platform's timeout.

In this repo:

- The `module "ise"` block in `infra/main.tf` is commented out. The ISE module code under `infra/modules/ise/` is preserved unchanged so the manual VM can be imported back into Terraform later.
- The `ise_private_ip` and `ise_ssh_key_path` outputs in `infra/outputs.tf` are commented out for the same reason.
- Step-by-step instructions for the Portal deploy live in `setup/ise-portal-deploy.md`. They include every field value the Portal asks for, including the `user_data` payload that ISE needs.
- After the Portal-deployed VM is running, you can run `terraform import module.ise.azurerm_linux_virtual_machine.this <vm-id>` to reattach it to state. (You will need to uncomment the module call and outputs first, and the import requires the existing NIC and keypair to be regenerated by the module first.)

**Things to revisit later:**

- Try `az vm create --no-wait` followed by `terraform import` as a fully-CLI alternative to the Portal click-through. This was not tried in this build because the Portal path was sufficient.
- Watch for a refreshed Cisco marketplace image. If Cisco updates the agent shipping inside the image, the Terraform path may start working without changes.
- Consider opening a Microsoft Azure support ticket to extend the OS provisioning timeout for marketplace images that have known long first-boot windows.

### Azure VMs only accept RSA SSH keys

**Symptom:** `terraform apply` fails creating a Linux VM with `the provided ssh-ed25519 SSH key is not supported. Only RSA SSH keys are supported by Azure`.

**Cause:** Azure's `azurerm_linux_virtual_machine.admin_ssh_key` field accepts RSA keys only. Ed25519 (which is the modern default for SSH key generation everywhere else) is rejected even though OpenSSH supports it. Microsoft has talked about adding Ed25519 support but it's not GA at the time of this build.

**Fix:** When generating an SSH key for an Azure VM via the `tls` provider, use `algorithm = "RSA"` with `rsa_bits = 4096`. Ed25519 works fine for connecting OUT of Azure VMs (e.g., outbound git SSH) — only the admin key on the VM itself has to be RSA.

### `AzureBastionSubnet` is a hard name requirement

**Symptom:** Bastion deployment fails with a confusing error about "subnet not found" or "invalid subnet."

**Cause:** Azure Bastion requires a subnet named exactly `AzureBastionSubnet`. Not `bastion-subnet`, not `snet-bastion` — the exact string. It's also size-constrained at /26 minimum.

**Fix:** The network module names it correctly. Don't rename it.

---

## FTDv and Cisco

### FTD 10 publishes under a new marketplace SKU

**Symptom:** You search the Azure marketplace for "Cisco FTDv 10" and find only 7.x versions. The 10.x deployment guide says to use a different plan name than what you find under the old SKU.

**Cause:** Cisco refactored their image publishing. Old SKUs (`ftdv-azure-*`) only ship 7.x. New SKUs (`cisco-ftdv-x86-*`) ship 10.x.

**Fix:** Use `cisco-ftdv-x86-byol` (or the PAYG equivalent) for FTD 10.x deploys. Documented in `setup/azure-setup.md` and pinned in `infra/variables.tf`.

### Day-0 JSON field is `FmcIp`, not `FmcIpAddress`

**Symptom:** FTDv boots but never registers with cdFMC. Manual `configure manager add` works fine, but the auto-registration path silently fails.

**Cause:** Older Cisco docs and ARM templates sometimes show the field as `FmcIpAddress`. The canonical name across every version from 6.5 to 10.0 is `FmcIp`. The wrong field name is silently ignored at boot.

**Fix:** Use `FmcIp` (no `Address` suffix). The FTDv module has the correct schema.

### `FirewallMode` is not a documented Day-0 field in 10.x

**Symptom:** Same as above — silent bootstrap failure or unexpected default mode.

**Cause:** Older docs included `FirewallMode: "Routed"` as a Day-0 field. The 10.x README from CiscoDevNet/cisco-ftdv does not list it. We don't know whether 10.x ignores it silently or rejects the JSON outright.

**Fix:** Removed `FirewallMode` from the Day-0 JSON. Routed mode is the default.

### NIC ordering is fixed and matters

**Symptom:** FTDv boots into a useless state where management is on the wrong interface or the data plane doesn't pass traffic.

**Cause:** Cisco assigns roles to NIC slots by position, not by name. nic0 is always management, nic1 is always diagnostic, nic2 is always outside (Gi0/1), nic3 is always inside (Gi0/2). Swapping them breaks the device.

**Fix:** The FTDv module attaches NICs in the right order. Don't reorder the `network_interface_ids` array in `azurerm_linux_virtual_machine`.

### Management interface has no Internet egress, so cdFMC sftunnel must source from the data interface

**Symptom:** FTDv is deployed and bootstrapped but cannot reach cdFMC. `configure manager add` runs without error but cdFMC never sees the device.

**Cause:** This demo deliberately keeps the management interface private (no public IP, no Internet egress). cdFMC is on the public Internet. By default, FTDv tries to source sftunnel traffic from the management NIC, which can't reach the Internet.

**Fix:** On the FTD CLI, run `configure network management-data-interface` and pick the outside interface. After that, `configure manager add` works. Documented in `setup/cdFMC-registration.md`.

### `DONTRESOLVE` is the long-standing sentinel for "register manually later"

**Symptom:** None per se — this is a heads-up. The 10.0 README from CiscoDevNet does not explicitly document `DONTRESOLVE` as a valid `FmcIp` value, even though older docs do.

**Cause:** `DONTRESOLVE` has been the de-facto pattern since FTD 6.x for telling the device "don't try to auto-register, I'll do `configure manager add` later." We're trusting it still works in 10.x; if it ever stops, the manual registration flow recovers cleanly.

**Fix:** If first-boot auto-registration fails, fall back to the manual `configure manager add` flow in `setup/cdFMC-registration.md`. No re-deploy needed.

---

## Entra ID

### Portal navigation moves around

**Symptom:** A guide tells you to go to **Properties** in the left nav, but Properties doesn't appear there. You're not sure if the doc is wrong or if you're looking in the wrong place.

**Cause:** Microsoft moves Entra portal nav around regularly. Some items become tabs on a parent page; others move under different sections. Older guides drift quickly.

**Fix:** Always check the current Microsoft Learn doc rather than trusting older third-party walkthroughs. As of this build: **Disable Security Defaults** lives at **Entra ID > Overview > Properties tab > Manage security defaults**. **Custom domains** lives at **Entra ID > Domain names**. If your portal differs, search Microsoft Learn for the feature name and the current path is in the article.

### certbot doesn't auto-reissue when going from staging to production

**Symptom:** You run `STAGING=1 scripts/generate-certs.sh` to validate the chain, then re-run `scripts/generate-certs.sh` for the real cert. certbot prints `Certificate not yet due for renewal; no action taken` and exits without issuing a new cert. The cert at `certs/config/live/ravpn-demo/` still has the staging issuer.

**Cause:** certbot's renewal logic checks "is the existing cert still valid?" not "was the existing cert issued by the same ACME server I'm about to ask?" Since the staging cert is still ~90 days from expiry, certbot decides there's nothing to do.

**Fix:** Pass `FORCE=1` on the production run:

```bash
FORCE=1 scripts/generate-certs.sh
```

The script translates this into certbot's `--force-renewal` flag, which makes certbot reissue regardless of expiry state. Burns 1 of your 5 weekly production-issuance attempts on `rooez.com`.

The same flag is what you'd use later if you ever needed to force a renewal mid-cycle for any other reason (e.g., key rotation).

### Curly quotes and `!` history expansion break shell exports

**Symptom:** You paste a curl command from chat or a doc into your terminal, and zsh returns `zsh: event not found: <something>` instead of running the command. Or the command runs but the env var contains weird Unicode characters that break the API call.

**Cause:** Two separate traps that often hit at the same time.

1. zsh expands `!` inside **double quotes** as history substitution. A password like `!Password1` triggers a history lookup for "Password1", which fails.
2. Some terminals, browsers, and paste tools auto-replace straight quotes (`"`) with curly/smart quotes (`"` `"`). They look identical at a glance. zsh treats curly quotes as literal characters in the value, not as quoting.

**Fix:** Use **single quotes** around any value containing `!` or special characters:

```bash
TRADER1_PASSWORD='!Password1'
```

Single quotes are completely literal in zsh — no history expansion, no variable substitution. If you must use double quotes, escape `!` with a backslash (`\!`).

When pasting commands from a doc, eyeball the quotes. If they're slanted (`"` `"`), retype them as straight (`"` or `'`).

This trap shows up most often in the ROPC curl test in `setup/entra-config.md` because trader1's password almost always contains a special character.

### Security Defaults blocks ROPC

**Symptom:** ISE auth against Entra fails. The curl ROPC test returns `invalid_grant` with a message about MFA or conditional access.

**Cause:** Security Defaults (on by default for new tenants since Oct 2019) forces MFA on every sign-in, including OAuth ROPC password flows. ROPC and MFA are architecturally incompatible — there's no browser to prompt the user.

**Fix:** Disable Security Defaults at **Entra ID > Overview > Properties tab > Manage security defaults**. The ZTAA path triggers MFA via the SAML AuthnRequest itself, so disabling Security Defaults doesn't compromise the demo's MFA story.

For tenants with Entra ID P1 or higher, use Conditional Access scoped to specific apps instead of disabling Security Defaults outright. P1 is not required for the workshop.

---

## DNS and Cloudflare

### Orange cloud breaks both demos

**Symptom:** RAVPN tunnel fails to establish. ZTAA SAML callback returns a TLS error. Both happen even though DNS resolves correctly.

**Cause:** Cloudflare's "proxied" mode (orange cloud) terminates TLS at Cloudflare's edge before the connection reaches your firewall. Secure Client expects to talk directly to the firewall; ZTAA SAML expects the firewall's cert; both fail.

**Fix:** Click the cloud icon next to each A record until it turns gray (DNS only). Confirm before every test.

---

## Local toolchain

### `alirezarezvani/claude-skills` plugin manifests are broken on install

**Symptom:** `/doctor` reports "Path escapes plugin directory: ./ (skills)" for `engineering-skills` and `engineering-advanced-skills`. None of the bundled skills load.

**Cause:** The marketplace ships those plugins with `"skills": "./"` in `plugin.json`, which Claude Code's loader rejects because `./` resolves to the plugin root and the loader requires a real subdirectory.

**Fix:** `scripts/fix-claude-skills-plugins.sh` patches the four affected `plugin.json` files (two in marketplace, two in cache) with explicit arrays of every skill subdirectory. Idempotent. Re-run after any `/plugin marketplace update` because updates re-pull the broken manifests.

### Terraform `required_version` constraint mismatched local install

**Symptom:** `terraform init` fails with "Unsupported Terraform Core version" pointing at the `required_version` line in `versions.tf`.

**Cause:** Pinned to `>= 1.6.0` originally; the local install was 1.5.7 because that's what `brew install terraform` installed at the time.

**Fix:** Lowered the constraint to `>= 1.5.0`. The HCL syntax we use works in both. PLAN.md still recommends 1.6+ as a baseline for new installs.

### `tsc -b` emits sibling `.js` files into `src/`

**Symptom:** After `npm run build`, you see `.js` and `.d.ts` files showing up next to every `.ts`/`.tsx` source file. Prettier and other tools start picking them up.

**Cause:** TypeScript's build mode (`tsc -b`) emits compiled artifacts by default. Vite handles its own transpilation, so we only want `tsc` for type-checking.

**Fix:** Set `"noEmit": true` in `app/tsconfig.json` and changed the build script to `tsc --noEmit && vite build`. No more stray files.

### jsdom doesn't implement `ResizeObserver`

**Symptom:** Vitest tests using Recharts fail with `ReferenceError: ResizeObserver is not defined`.

**Cause:** Recharts' `ResponsiveContainer` calls `new ResizeObserver(...)` at mount. jsdom doesn't ship a `ResizeObserver` polyfill.

**Fix:** Stub it in `app/src/test-setup.ts`. The stub does nothing because we're not actually measuring anything in tests.

```ts
class ResizeObserverStub {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}
globalThis.ResizeObserver = globalThis.ResizeObserver ?? ResizeObserverStub;
```

---

## Workflow and process

### Pushing to GitHub after every commit

This isn't a fix for a problem so much as a working pattern that's saved time. Mario adopted "push after every commit" for this repo so each change is mirrored to GitHub immediately. The trade-off is more push events, but the upside is no surprises about what's local versus published. The standing instruction lives in auto-memory and applies only to this repo.

### Skills are loaded but not preloaded into context

Loading every available skill upfront dumps tens of thousands of tokens of playbook for work that hasn't started. The pattern that works: invoke a skill at the start of the work block it covers (`terraform-patterns` when opening `infra/`, `senior-frontend` when opening `app/`, etc.). Skills also auto-trigger when their description matches the request, so you usually don't need to invoke them by name.
