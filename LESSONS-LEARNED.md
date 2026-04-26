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

**Cause:** Azure has two layers of quota in the same region. Per-family caps say "you can have N vCPUs of this VM family." A separate **Total Regional vCPUs** cap says "across every family combined, no more than N vCPUs." The default for a new subscription is 10. This demo needs 17 (FTDv 8 + ISE 8 + app 1).

**Fix:** Request a quota increase via the Azure portal (Subscriptions > your subscription > Usage + quotas > filter to your region > "Total Regional vCPUs"). Ask for at least 24 to give yourself headroom. Approval is usually quick on default-tier subscriptions.

`scripts/preflight.sh` checks this before every deploy.

### Marketplace terms are per-SKU, not per-publisher

**Symptom:** Terraform fails to deploy a VM with "marketplace terms not accepted" even though you accepted terms for what you thought was the same image earlier.

**Cause:** Cisco publishes FTDv under multiple marketplace SKU names: the legacy `ftdv-azure-byol`/`ftdv-azure-payg` (for FTD 7.x and earlier) and the newer `cisco-ftdv-x86-byol`/`cisco-ftdv-x86-payg` (for FTD 10.x). Accepting terms for one does not carry over to the other. Same publisher, same offer name, different SKU.

**Fix:** Run `az vm image terms accept` for the exact plan name in `infra/variables.tf`. Today that's `cisco-ftdv-x86-byol` for FTDv and `cisco-ise_3_5` for ISE. If you switch the SKU, accept the new terms before re-running apply.

### "admin" is a reserved username on Azure VMs

**Symptom:** `terraform validate` succeeds, but `terraform apply` fails immediately with a long error listing reserved usernames including "admin", "administrator", "user", and a few dozen others.

**Cause:** Azure refuses to provision a VM with `admin_username` set to common values that attackers spray.

**Fix:** Pick something else. The FTDv module uses `cisco` as the Azure-side admin username. The actual FTD admin login (the one you SSH in with) is set by the Day-0 JSON's `AdminPassword` field, which is unrelated to Azure's `admin_username`.

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
