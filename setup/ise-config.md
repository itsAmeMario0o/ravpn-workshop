# ISE config

REST ID against Entra, FTDv as a NAD, auth and authz policies for RAVPN.

## Prerequisites

- ISE first boot complete (45-60 min from `terraform apply`).
- Entra App Registration exists with tenant ID, client ID, and client secret available (see `entra-config.md`).
- FTDv registered to cdFMC.
- Bastion access to ISE.

## 1. Reach the ISE GUI

ISE GUI listens on 443 of its private IP. Tunnel through Bastion:

```bash
ISE_PORT=443 scripts/bastion-tunnel.sh ise 50443
```

In another terminal:

```
open https://127.0.0.1:50443
```

Sign in as `iseadmin` with the password from `ise_admin_password`.

## 2. REST ID identity store

**Administration > Identity Management > External Identity Sources > REST**

- Name: `Entra-REST`
- Authentication endpoint URL: `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token`
- Username Suffix: blank (the username comes through as `trader1@rooez.com`)
- Client ID and Client Secret: from the Entra App Registration.
- Scope: `https://graph.microsoft.com/.default`

Save. Use the **Test Connection** button to confirm.

## Verify

Test against `trader1@rooez.com` from within REST settings. Expected: success.

## 3. Add FTDv as a Network Access Device

**Administration > Network Resources > Network Devices > Add**

- Name: `ftdv-ravpn`
- IP address: `10.100.2.10` (FTDv outside; this is what FTD sources RADIUS from)
- Device type: any
- RADIUS shared secret: pick a strong value. You will paste this into cdFMC for the AAA server group.

Save the shared secret in your password manager. cdFMC needs the same string.

## 4. Auth policy

**Policy > Policy Sets**

- Create a policy set named `RAVPN-Demo`.
- Conditions: `RADIUS:NAS-IP-Address EQUALS 10.100.2.10`
- Default authentication: use `Entra-REST` as the identity source.

## 5. Authz policy

Inside the same policy set:

- Rule: `Permit-RAVPN`
- Condition: any successful authentication against `Entra-REST`.
- Result: `PermitAccess`

## Verify

From the FTDv CLI (via Bastion), run a RADIUS test:

```
> test aaa-server authentication ise host 10.100.4.10 username trader1@rooez.com password '<password>'
```

Expected: `Authentication Successful`.

In ISE: **Operations > RADIUS > Live Logs** should show the test record with `PermitAccess`.

## Troubleshooting

- **Test Connection fails on REST ID:** confirm Entra App Registration permissions and that `Allow public client flows = Yes`.
- **Authentication fails but Test Connection works:** the user may have MFA enabled. ROPC and MFA are incompatible.
- **No RADIUS Live Log entry:** shared-secret mismatch between FTDv and ISE NAD record.
