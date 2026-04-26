# Entra ID config

Demo user, MFA, ZTAA Enterprise App, ISE App Registration.

Two identity flows live here:

- RAVPN uses ROPC (Resource Owner Password Credentials). No MFA.
- ZTAA uses SAML + MFA via Microsoft Authenticator.

## 1. Custom domain

If `rooez.com` is not yet a verified domain on the Entra tenant, add it under **Identity > Settings > Domain names**. Follow the TXT-record verification flow.

## Verify

The domain shows **Healthy** in the domain list.

## 2. Demo user

Create `trader1@rooez.com`:

- **Identity > Users > New user > Create new user**
- User principal name: `trader1@rooez.com`
- Display name: `Trader One`
- Set a temporary password, force change on first sign-in.

Sign in once at `https://login.microsoftonline.com` to set the permanent password and enroll in Microsoft Authenticator.

## Verify

The user can sign in and complete an MFA prompt via Authenticator.

## 3. ZTAA Enterprise App (SAML)

- **Identity > Enterprise applications > New application > Create your own application**
- Name: `RAVPN-ZTAA-Trading`
- Choose **Integrate any other application you don't find in the gallery**.
- After creation: **Single sign-on > SAML**
  - Identifier (Entity ID): `https://[AppGroupName].rooez.com`
  - Reply URL (ACS URL): `https://[AppGroupName].rooez.com/SAML/sso/login`
  - Sign-on URL: `https://trading.rooez.com/ztaa`
- Download **Federation Metadata XML**. cdFMC consumes this.
- Assign `trader1@rooez.com` under **Users and groups**.

Replace `[AppGroupName]` with the real application group name in the cdFMC SSO Server Object. The two strings must match exactly.

## Verify

The Enterprise App appears under **Enterprise applications** with `trader1` assigned.

## 4. ISE App Registration (ROPC)

- **Identity > Applications > App registrations > New registration**
- Name: `ISE-REST-ID-ROPC`
- Supported account types: single tenant
- Redirect URI: leave blank
- Create.

After creation:

- **Authentication > Allow public client flows = Yes**
- **API permissions > Add a permission > Microsoft Graph > Delegated > User.Read** (admin consent).
- **Certificates & secrets > New client secret**. Copy the **Value** immediately.

## Save these for ISE

| Field | Where to find |
|---|---|
| Tenant ID | App registration overview |
| Client ID (Application ID) | App registration overview |
| Client secret | Certificates & secrets > Value (only visible once) |

## Verify

Test the ROPC flow with curl:

```bash
curl -X POST "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
  -d "grant_type=password" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "username=trader1@rooez.com" \
  -d "password=$TRADER1_PASSWORD" \
  -d "scope=https://graph.microsoft.com/.default"
```

Expected: a JSON response with `access_token`. If this fails, ISE auth will fail too. Fix here first.

## Notes

- ROPC and MFA are incompatible by design. Do not enable MFA for `trader1@rooez.com` if you want RAVPN to work via ROPC. ZTAA will still trigger MFA via the SAML flow.
- The client secret expiration defaults to 6 months. For a demo, the default is fine.
