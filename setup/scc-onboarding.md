# SCC pre-provisioning and license claim

This step happens **before** `terraform apply`. We tell Security Cloud Control (SCC) "an FTDv with this name is going to register itself to cdFMC soon — here's the registration key and NAT ID it should use." SCC creates a pending device record. Later, after `terraform apply` brings the real FTDv online, you SSH to it via Bastion and run the matching `configure manager add` command. The pending record turns into a registered device.

This doc covers the SCC half of that flow. The FTDv half lives in [cdFMC-registration.md](cdFMC-registration.md).

## Before you start

You need:

- An SCC tenant with cdFMC provisioned (most workshops have this already).
- Your Cisco SSO sign-in for SCC.
- (Optional but worth checking) A Smart Account / Virtual Account linked to SCC, with whatever entitlements you want to claim for this device.

### Check Smart Account linkage (optional)

If you want to use real licenses (instead of the 90-day evaluation that comes free), confirm SCC is linked to your Smart Account.

1. Sign in to SCC at `https://security.cisco.com`.
2. Top-right corner → click your profile icon → **Settings** (or the gear icon).
3. Look for **Smart Licensing**, **Cisco Smart Account**, or **License Settings**.
4. If linked, you'll see the Smart Account name and Virtual Account.

If you skip this check or aren't linked, the 90-day eval period covers everything you'll claim during onboarding. It's the simplest path for a workshop.

## Step 1 — Onboard a pending FTDv

1. Sign in to SCC at `https://security.cisco.com`.
2. Left-hand nav: click **Security Devices** (some SCC versions label this **Inventory** — same destination).
3. Top right → click **+ Onboard** (or the cloud-with-plus icon labeled "Onboard device or service").
4. The onboarding gallery opens. Click the **FTD** tile.
5. SCC asks how you want to onboard. Pick **Use CLI Registration Key**.

## Step 2 — Fill in device details

A multi-step wizard appears.

| Field | Value |
|---|---|
| **Device Name** | `ftdv-ravpn` (matches the VM name in `infra/main.tf`; keep it consistent) |
| **Policy Assignment** | Pick a default Access Control Policy if one exists, or skip — we configure real policies in cdFMC later in Phase 5. |

Click **Next**.

## Step 3 — Claim the right licenses

This is the step most people get wrong. Cisco's licensing model is **per-feature**: cdFMC only enables a feature if the device has explicitly claimed the relevant license. Even if the feature exists in the firmware, leaving the box unticked here means it stays disabled — even in evaluation mode.

For this workshop, tick **all four**:

| License | Why we need it |
|---|---|
| **Threat (Essentials)** | NGFW basics: IPS, application visibility. The "T" in TMC. |
| **URL Filtering** | Category-based URL allow/block. The "U" in TMC. |
| **Malware Defense** | File-trajectory and AMP integration. The "M" in TMC. |
| **Cisco Secure Client Premier** | RAVPN, ZTAA, posture-aware VPN. **Without this box ticked, RAVPN and ZTAA stay disabled.** Older SCC versions label this as **AnyConnect Apex** or **AnyConnect Premier** — same thing. |

**Real-world entitlement vs evaluation:**

You may have real entitlements for some licenses but not others. That's fine — claim everything you need on the device, regardless of what your Smart Account actually has. Cisco's licensing engine does this:

- For features where the Smart Account has the entitlement: feature is fully licensed.
- For features where the Smart Account does **not** have the entitlement: cdFMC enters the **90-day evaluation grace period** for that feature. Works as if the license were present, no warnings, full functionality.

After 90 days, evaluated-but-unlicensed features stop working until either (a) you acquire the real entitlement, or (b) you destroy the device. For a one-day workshop, the eval window is plenty.

Click **Next**.

## Step 4 — Copy what SCC gives you

On the final step, SCC displays a CLI command that looks like this (your specific values will differ):

```
configure manager add <scc-fqdn> <REG_KEY> <NAT_ID> <DEVICE_NAME>
```

Three things to copy from this screen:

| Value | What you do with it |
|---|---|
| Full `configure manager add ...` command | Paste into your password manager. You'll run this exact string on the FTD CLI in Phase 4 ([cdFMC-registration.md](cdFMC-registration.md)). |
| `<REG_KEY>` (the reg key alone) | Goes into `terraform.tfvars` as `ftdv_reg_key`. |
| `<NAT_ID>` (the NAT ID alone) | Goes into `terraform.tfvars` as `ftdv_nat_id`. |

The reg key is typically a 30-32 character random alphanumeric string. The NAT ID is similar. Both are case-sensitive.

After you copy, finish the wizard. SCC saves the pending device record.

## Verify

In SCC: **Security Devices** lists the new device with status **Pending Setup** or **Pending Registration**. The device sits there waiting until the real FTDv registers in Phase 4.

## What if I forgot to tick Cisco Secure Client Premier?

Two recovery paths.

### Before FTDv registers

1. SCC → **Security Devices** → click the pending row.
2. Look for **Licenses**, **Subscription Licenses**, or **Edit Licenses** in the side panel.
3. Tick **Cisco Secure Client Premier** → save.

Some SCC versions lock the license selection on pending records. If yours does, use the post-registration path below.

### After FTDv registers

1. cdFMC → **System > Licenses > Smart Licenses**.
2. Find the FTDv device row.
3. Click **Edit Licenses** (pencil icon).
4. Tick **Cisco Secure Client Premier**.
5. Apply.

Same outcome either way — RAVPN/ZTAA features unlock once the box is ticked and policy is deployed.

## Things to save before you leave SCC

| Field | Where it goes |
|---|---|
| Full `configure manager add ...` command | Password manager. Used in Phase 4. |
| Reg key | `infra/terraform.tfvars` as `ftdv_reg_key` |
| NAT ID | `infra/terraform.tfvars` as `ftdv_nat_id` |
| SCC FQDN (the first arg of the command) | Reference only — used by the FTD CLI command, not by Terraform |

## When licenses might block you

For a one-day workshop with the 90-day eval covering missing entitlements, licensing should not block any demo. If something does fail with a license error, the symptom is usually:

- cdFMC says "Smart License is not registered" → the FTDv hasn't completed Smart Licensing handshake. Wait 5-10 minutes after registration; cdFMC retries automatically.
- A specific feature (RAVPN, ZTAA) is greyed out in cdFMC → the corresponding license claim was missed. Use the post-registration recovery path above.
- "Out of Compliance" warnings on the device → eval period expired or claim is missing. For a workshop on a fresh device, this should not happen.

PLR (Permanent License Reservation) and SLR (Specific License Reservation) are options for **air-gapped** environments — devices that can't reach Cisco's licensing servers. For a cloud demo with Internet egress, you don't need either. Skip both.
