# ISE config

ISE sits between the firewall and Entra ID. When a user dials in over RAVPN, the firewall sends a RADIUS request to ISE. ISE looks at the user, decides which identity store to check, and (in our case) hands the password off to Entra over OAuth ROPC. Entra answers yes or no. ISE turns that into a RADIUS Accept or Reject, and the firewall completes the tunnel.

There are three things to configure: the identity store that points at Entra, the firewall as a network access device, and the policy that ties the two together.

## Before you start

For steps 1-5 (configuring ISE itself):

- ISE has finished its first boot. The Portal walkthrough (`setup/ise-portal-deploy.md`) ends with a `show application status ise` check — every non-disabled service should be in `running` state before you start here.
- The Entra App Registration exists and you have the tenant ID, client ID, and client secret saved. See [entra-config.md](entra-config.md).
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

## 2. Enable REST Auth Service

ISE has a feature called **REST Auth Service** that powers REST-based identity sources. If you run `show application status ise` from the ISE CLI, this service shows as `disabled` by default. The bootstrap fields we passed in user_data (`ersapi=yes`, `openapi=yes`, `pxGrid=yes`) cover three other APIs but **not** REST Auth Service. It has to be turned on in the GUI before the REST identity source we create in step 3 will work.

In the ISE GUI:

**Administration > System > Settings > Protocols > REST Auth Service**

Set:

- **Enable REST Auth Service:** toggle to **on**
- Save

After save, ISE restarts the REST Auth Service in the background. This takes about a minute. To confirm it came up, run `show application status ise` again from the CLI — `REST Auth Service` should now read `running`.

If you do not enable this first, the **Test Connection** button in step 3 will fail with a generic "REST service unavailable" error and you will spend a long time looking at Entra config that is not the problem.

## 3. Create the REST ID identity store

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

## 4. Add FTDv as a Network Access Device

ISE only accepts RADIUS from devices it knows about.

**Administration > Network Resources > Network Devices > Add**

- Name: `ftdv-ravpn`
- IP address: `10.100.2.10`. This is the FTDv outside interface, which is what FTD sources its RADIUS traffic from.
- Device type: any.
- RADIUS shared secret: choose a strong value.

Save the shared secret somewhere safe. cdFMC needs the same string when you create the AAA server group.

## 5. Build the policy set

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
