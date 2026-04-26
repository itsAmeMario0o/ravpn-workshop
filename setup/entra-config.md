# Entra ID config

This is the most fiddly step. You will configure Entra ID three times for three different reasons:

- Add `rooez.com` as a custom domain on the tenant.
- Create one demo user (`trader1@rooez.com`) and enroll them in MFA.
- Set up two separate identity integrations: one Enterprise App for ZTAA's SAML flow, and one App Registration for ISE's REST ID flow.

The two integrations exist because the two demos use different protocols on purpose:

- **RAVPN** uses **ROPC** (Resource Owner Password Credentials). The user's password goes from FTD to ISE to Entra. There is no MFA on this path. ROPC and MFA are incompatible by design.
- **ZTAA** uses **SAML** with **MFA**. The browser is redirected to Entra, which prompts for the password and an Authenticator push, then redirects back to the firewall.

Showing both flows side by side is the whole point of the workshop. Do not try to add MFA to the RAVPN path. It will not work.

## 1. Add the custom domain

If `rooez.com` is not already a verified domain on the Entra tenant, add it.

Go to **Identity > Settings > Domain names**, click **Add custom domain**, enter `rooez.com`. Entra gives you a TXT record to add to Cloudflare. Add it, wait a minute, click **Verify**.

## Verify

The domain shows **Healthy** in the domain list.

## 2. Create the demo user

**Identity > Users > New user > Create new user**

- User principal name: `trader1@rooez.com`
- Display name: `Trader One`
- Password: assign a temporary one and require change on first sign-in.

Sign in as `trader1` once at `https://login.microsoftonline.com`. Set the permanent password, and when prompted, enroll in Microsoft Authenticator.

## Verify

`trader1` can sign in and complete an MFA prompt via Authenticator.

## 3. Create the ZTAA Enterprise App (SAML)

This is the SAML federation between the firewall and Entra.

**Identity > Enterprise applications > New application > Create your own application**

- Name: `RAVPN-ZTAA-Trading`
- Choose **Integrate any other application you don't find in the gallery**.

After it's created, open the app and go to **Single sign-on > SAML**:

- Identifier (Entity ID): `https://[AppGroupName].rooez.com`
- Reply URL (ACS URL): `https://[AppGroupName].rooez.com/SAML/sso/login`
- Sign-on URL: `https://trading.rooez.com/ztaa`

Download the **Federation Metadata XML**. cdFMC will consume this file when you create the SSO Server Object later.

Assign `trader1@rooez.com` to the app under **Users and groups**.

The literal `[AppGroupName]` is a placeholder. You will replace it with a real value when you create the cdFMC Application Group. The two strings, in Entra and cdFMC, must match exactly.

## Verify

The app appears under **Enterprise applications** with `trader1` in the assigned users list.

## 4. Create the ISE App Registration (ROPC)

This is the OAuth integration ISE uses to validate passwords against Entra.

**Identity > Applications > App registrations > New registration**

- Name: `ISE-REST-ID-ROPC`
- Supported account types: single tenant.
- Redirect URI: leave blank.

After creation:

- **Authentication > Allow public client flows = Yes**. ROPC is a public client flow.
- **API permissions > Add a permission > Microsoft Graph > Delegated > User.Read**, then click **Grant admin consent**.
- **Certificates & secrets > New client secret**. Copy the **Value** immediately — you cannot see it again after you leave this page.

Save these three things, ISE needs all of them:

| Field | Where to find it |
|---|---|
| Tenant ID | App registration overview |
| Client ID | App registration overview, labeled "Application (client) ID" |
| Client secret | The Value column on the secret you just created |

## Verify

Test the ROPC flow with curl before you touch ISE. If this fails here, ISE will fail too, and ISE has worse error messages.

```bash
curl -X POST "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
  -d "grant_type=password" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "username=trader1@rooez.com" \
  -d "password=$TRADER1_PASSWORD" \
  -d "scope=https://graph.microsoft.com/.default"
```

A successful response is a JSON object with an `access_token` field. If you get an error mentioning conditional access or MFA, the user has MFA enabled and ROPC will not work for them.

## Notes

- The client secret default expiration is 6 months. For a workshop, the default is fine. Note the date so you do not get surprised later.
- ROPC is a deprecated flow Microsoft does not love, but it is still supported. ISE depends on it for this kind of integration. The production-grade alternative is EAP-TLS with certificates, which is out of scope for this workshop.
