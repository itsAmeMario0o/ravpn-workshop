# ISE config

ISE sits between the firewall and Entra ID. When a user dials in over RAVPN, the firewall sends a RADIUS request to ISE. ISE looks at the user, decides which identity store to check, and (in our case) hands the password off to Entra over OAuth ROPC. Entra answers yes or no. ISE turns that into a RADIUS Accept or Reject, and the firewall completes the tunnel.

There are three things to configure: the identity store that points at Entra, the firewall as a network access device, and the policy that ties the two together.

## Before you start

For steps 1-5 (configuring ISE itself):

- ISE has finished its first boot. The Portal walkthrough (`setup/ise-portal-deploy.md`) ends with a `show application status ise` check — every non-disabled service should be in `running` state before you start here.
- The Entra App Registration exists and you have the **tenant ID**, **client ID**, and **client secret value** saved. See [entra-config.md](entra-config.md). All three are GUIDs except the secret value, which is an opaque string Entra only displays once when you generate it.
- The Bastion script works (`setup/bastion-access.md`).

For the **Verify** step at the end (testing RADIUS end-to-end):

- FTDv is registered to cdFMC.
- The cdFMC AAA server group for ISE is configured (this happens during RAVPN setup, after this guide).

Steps 1-5 do not depend on FTDv being registered. Do them now. The Verify step uses `test aaa-server` from the FTDv CLI, which only becomes useful after the firewall has the ISE shared secret configured through cdFMC. Come back and run Verify after `setup/cdFMC-registration.md` is done and the RAVPN AAA group is built.

A note on auth methods. The underlying Linux `iseadmin` user is protected by an SSH key (saved at `keys/ise_admin` from the Portal-deploy step). You only need that key if you SSH directly to ISE on port 22 to manage the underlying OS — uncommon for a workshop. The **ISE web UI** on port 443 and the **ISE CLI** (different from the underlying Linux shell) both use the password you set in `ise_admin_password` in `terraform.tfvars`. That's the password you sign in with as `iseadmin` in this guide.

## 1. Reach the ISE web UI

ISE serves its UI on port 443 of its private IP. Tunnel through Bastion:

```bash
ISE_PORT=443 scripts/bastion-tunnel.sh ise 50443
```

Leave that running. In your browser:

```
https://127.0.0.1:50443
```

Accept the cert warning (ISE's self-signed cert is fine for the demo). Sign in as `iseadmin` with the password you set in `ise_admin_password`.

## 2. Enable REST ID Store

In ISE 3.3, the REST Identity Store feature is gated behind a global enable toggle. Until you flip it on, the REST entry does not appear under External Identity Sources.

In the ISE GUI:

**Administration > System > Settings**

In the left navigation tree of the Settings page, find **REST ID Store**. (Older ISE builds called this "REST Auth Service" and put it under "Protocols" — that location is gone in 3.3. The 3.3 wording is "REST ID Store" and it is its own top-level entry under Settings, not nested under Protocols.)

On the right pane:

- Toggle **Enable REST ID Store** to **on**
- Click **Save**

ISE applies the change in a few seconds. After save, the **REST** entry becomes visible under External Identity Sources (step 3 below).

The user_data we passed during the ISE Portal deploy (`ersapi=yes`, `openapi=yes`, `pxGrid=yes`) enabled three other APIs (External RESTful Services, Open API, pxGrid) — those are management APIs and are unrelated to REST ID Store. The REST ID Store toggle is the only thing that matters for the Entra integration.

If you skip this step, you will get a confusing "REST source type not found" error in step 3 and spend a long time looking at the wrong thing.

## 3. Create the REST ID identity source

This is the bridge between ISE and Entra ID. ISE 3.3 ships a built-in **Azure Identity Store** provider type that handles the OAuth ROPC endpoint URL internally — you do not have to type the raw `login.microsoftonline.com/.../oauth2/v2.0/token` URL like older ISE builds required.

**Administration > Identity Management > External Identity Sources > REST**

Click **Add** (or use the guided walkthrough if ISE 3.3 offers one — it walks the same fields).

Fields:

| Field | Value | Notes |
|---|---|---|
| Name | `ENTRA_ID` | Free-text name. Whatever you pick, you reference it later in the policy set's Authentication rule. |
| Description | (optional) `OAuth ROPC against Entra ID` | |
| REST Identity Provider | **`Azure Identity Store`** | Dropdown. ISE 3.3 ships this provider type with the Entra OAuth flow built in. |
| Client ID | The Entra App Registration's **Application (client) ID** GUID | From `entra-config.md` |
| Client Secret | The Entra App Registration's **client secret value** | The actual opaque string, not the secret ID. Entra hides this after generation; if you didn't save it, generate a new secret. |
| Tenant ID | The Entra **tenant ID** GUID | Found at App Registration > Overview > Directory (tenant) ID |
| Username Suffix | **leave blank** | Workshop attendees type the full UPN `trader1@rooez.com` in Cisco Secure Client. ISE forwards the username unchanged to Entra. If you set a suffix, ISE will append it and Entra will reject `trader1@rooez.com@rooez.com`. |

Click **Save**.

Skip the **Test Connection** button on the wizard's final screen for now. We will test after step 4 (NAD added) — testing in isolation produces confusing errors that aren't actually about REST config.

## 4. Add FTDv as a Network Access Device

ISE only accepts RADIUS from devices it knows about.

**Administration > Network Resources > Network Devices > + Add**

| Field | Value |
|---|---|
| Name | `ftdv-ravpn` |
| Description | (optional) `FTDv outside interface — Azure RAVPN demo` |
| IP Address | `10.100.2.10` (mask `32`) — this is the FTDv outside interface, which is what FTD sources RADIUS traffic from |
| Device Profile | `Cisco` |
| Network Device Group: Location / Device Type | leave defaults |
| RADIUS Authentication Settings (expand and enable) | |
| Protocol | `RADIUS` |
| Shared Secret | **Pick a strong value (24+ random characters) and write it down in your password manager.** cdFMC needs this exact string later when you create the AAA server group. If even one character differs, RADIUS Live Logs show no entries and auth silently fails. |
| CoA Port | `1700` (default) |

Click **Submit**. The new `ftdv-ravpn` row appears in the Network Devices list.

## 5. Build the policy set

This is the rule that ties the FTDv (NAD) to Entra (identity source). It has three layers — the outer policy set, plus an authentication rule and an authorization rule inside it.

### 5a. Create the policy set

**Policy > Policy Sets > + Add**

| Field | Value |
|---|---|
| Name | `RAVPN-Demo` |
| Description | (optional) `RADIUS authentication for RAVPN sessions from FTDv` |
| Conditions | `Radius·NAS-IP-Address Equals 10.100.2.10` |
| Allowed Protocols / Server Sequence | `Default Network Access` |

Save the row. `RAVPN-Demo` appears above `Default` in the policy set list.

### 5b. Authentication policy

Drill into `RAVPN-Demo` (the `>` chevron on the right of the row).

In the **Authentication Policy** section, expand the existing `Default` rule:

- **Use** column → select `ENTRA_ID` (the REST identity source from step 3)
- Save the row

### 5c. Authorization policy

In the **Authorization Policy** section, click **+ Add** to create a new rule above the default `DenyAccess` row:

| Field | Value |
|---|---|
| Rule Name | `Permit-RAVPN` |
| Conditions | (see "RADIUS attributes" note below — minimum is empty/Any; recommended is `Cisco-VPN3000-Client-Type Equals 2`) |
| Profiles | `PermitAccess` |
| Security Groups | leave default / blank |

Save the row. Drag it **above** the `Default` `DenyAccess` rule using the handle on the left side of the row. Page-level **Save** at the bottom-right of the policy set page commits everything.

### 5d. RADIUS attributes — coarse outer match, fine inner authorization

Cisco's RADIUS-from-FTD attribute pattern follows a hierarchy. Use it as designed:

| Attribute | Where | What it does |
|---|---|---|
| `Radius·NAS-IP-Address` (IETF #4) | **Outer Policy Set condition** (already set in step 5a) | Coarse "is this RADIUS from our FTD?" filter. The standard IETF attribute every RADIUS client sends. |
| `Cisco-VPN3000-Client-Type` (Cisco VSA #150) | Optional inside Authorization rule | Restrict to AnyConnect SSL VPN sessions only. Value `2` = SSL VPN, `6` = IPsec. |
| `Cisco·cisco-av-pair` containing `tunnel-group-name=` (Cisco VSA #146) | Optional inside Authorization rule | Differentiate by RAVPN connection profile / tunnel group. Useful when you add the geolocation second connection profile in a later phase. |
| `Cisco-VPN3000-Session-Type` (Cisco VSA #151) | Optional inside Authorization rule | Same SSL/IPsec distinction at the session level. |

Adding `Cisco-VPN3000-Client-Type Equals 2` to the `Permit-RAVPN` rule is the production-shaped recommendation — it enforces "only AnyConnect SSL VPN sessions get authorized," not just "any RADIUS request from this FTD." Skip it for the simplest demo path; add it when you want best-practice or before introducing the geolocation profile.

## Verify

(Run this only after FTDv is registered to cdFMC and the RAVPN AAA group is configured — both happen in `setup/cdFMC-registration.md` and the cdFMC RAVPN setup that follows.)

Test from the FTDv CLI through Bastion:

```
> test aaa-server authentication ise host 10.100.4.10 username trader1@rooez.com password '<password>'
```

Expected: `Authentication Successful`.

In the ISE web UI, **Operations > RADIUS > Live Logs** shows the test record with a green check and `PermitAccess`. If you see no Live Log entry at all, the shared secret between FTDv and ISE doesn't match.

## When it gets stuck

- **REST entry not visible under External Identity Sources:** you skipped step 2. Toggle REST ID Store enable in Settings, then refresh the External Identity Sources page.
- **Test Connection fails on REST ID:** check the Entra App Registration permissions. Confirm `Allow public client flows = Yes` in Entra. Confirm the client secret value (not the secret ID) was used.
- **Test Connection succeeds but live auth fails:** the user has MFA enabled. ROPC and MFA cannot coexist for the same user.
- **Entra rejects with `AADSTS50034 user does not exist` and the username has `@rooez.com@rooez.com` in the error:** Username Suffix is set in the REST ID config but the attendee also typed the full UPN. Either clear the suffix or instruct attendees to type just the shortname. Pick one.
- **No RADIUS Live Log entry:** the FTDv's RADIUS shared secret in cdFMC does not match the one in ISE's Network Device record. Both must be byte-for-byte identical.
