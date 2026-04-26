# ISE config

ISE sits between the firewall and Entra ID. When a user dials in over RAVPN, the firewall sends a RADIUS request to ISE. ISE looks at the user, decides which identity store to check, and (in our case) hands the password off to Entra over OAuth ROPC. Entra answers yes or no. ISE turns that into a RADIUS Accept or Reject, and the firewall completes the tunnel.

There are three things to configure: the identity store that points at Entra, the firewall as a network access device, and the policy that ties the two together.

## Before you start

- ISE has finished its first boot. This takes 45 to 60 minutes after `terraform apply`. You can tell because the web UI starts responding.
- The Entra App Registration exists and you have the tenant ID, client ID, and client secret saved. See [entra-config.md](entra-config.md).
- FTDv is registered to cdFMC.
- The Bastion script works.

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

## 2. Create the REST ID identity store

This is the bridge between ISE and Entra ID.

**Administration > Identity Management > External Identity Sources > REST**

Fields:

- Name: `Entra-REST`
- Authentication endpoint URL: `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token`
- Username Suffix: leave blank. The username comes through as `trader1@rooez.com` already.
- Client ID: from the Entra App Registration.
- Client Secret: from the Entra App Registration.
- Scope: `https://graph.microsoft.com/.default`

Save. Use the **Test Connection** button to confirm ISE can talk to Entra.

## Verify

In the REST settings, run a test against `trader1@rooez.com` with the user's password. Expected: success.

If this fails, ISE auth will fail. Stop here and fix it.

## 3. Add FTDv as a Network Access Device

ISE only accepts RADIUS from devices it knows about.

**Administration > Network Resources > Network Devices > Add**

- Name: `ftdv-ravpn`
- IP address: `10.100.2.10`. This is the FTDv outside interface, which is what FTD sources its RADIUS traffic from.
- Device type: any.
- RADIUS shared secret: choose a strong value.

Save the shared secret somewhere safe. cdFMC needs the same string when you create the AAA server group.

## 4. Build the policy set

**Policy > Policy Sets**, create a new policy set named `RAVPN-Demo`.

- Conditions: `RADIUS:NAS-IP-Address EQUALS 10.100.2.10`
- Default authentication: use `Entra-REST` as the identity source.

Inside the policy set, add an authorization rule:

- Rule: `Permit-RAVPN`
- Condition: any successful authentication against `Entra-REST`.
- Result: `PermitAccess`

Save and activate the policy.

## Verify

Test from the FTDv CLI through Bastion:

```
> test aaa-server authentication ise host 10.100.4.10 username trader1@rooez.com password '<password>'
```

Expected: `Authentication Successful`.

In the ISE web UI, **Operations > RADIUS > Live Logs** shows the test record with a green check and `PermitAccess`. If you see no Live Log entry at all, the shared secret between FTDv and ISE doesn't match.

## When it gets stuck

- **Test Connection fails on REST ID:** check the Entra App Registration permissions. Confirm `Allow public client flows = Yes`.
- **Test Connection succeeds but live auth fails:** the user has MFA enabled. ROPC and MFA cannot coexist for the same user.
- **No RADIUS Live Log entry:** the FTDv's RADIUS shared secret in cdFMC does not match the one in ISE's Network Device record. Both must be byte-for-byte identical.
