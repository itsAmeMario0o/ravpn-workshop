# Entra ID config

This is the most fiddly step in the build. You'll touch the Entra portal seven times. Each one matters; skipping or fudging any of them shows up later as a confusing failure in ISE or ZTAA.

The whole point of this step is to set up two **separate** identity integrations on the same Entra tenant:

- **ZTAA uses SAML with MFA.** The browser is redirected to Entra, the user signs in with password and Microsoft Authenticator, and Entra sends a signed assertion back. This is what the workshop demonstrates as the "modern, zero-trust" path.
- **RAVPN uses ROPC.** The username and password go from ISE directly to Entra over OAuth, no browser, no MFA. This is what ISE supports for RADIUS-style integrations. ROPC and MFA are architecturally incompatible — you cannot prompt for an Authenticator push when there's no browser. RAVPN is intentionally password-only here.

Showing both flows side by side is the whole point. Do not try to add MFA to the RAVPN path. It will not work.

You sign in to the Entra admin center at `https://entra.microsoft.com` with the same account you used for `az login`.

---

## Step 1 — Confirm your tenant

Top-left of the Entra portal shows your tenant info. Note three things:

- **Tenant ID** — a 32-character GUID. Same value `az account show` returned. ISE needs this later as part of the REST ID URL.
- **Primary domain** — likely `<something>.onmicrosoft.com`. We're about to add `rooez.com` alongside it as a verified custom domain.
- **License** — under **Identity > Overview > Licenses**. Most likely **Microsoft Entra ID Free**, which is what every Azure subscription includes. Free is fine for this workshop.

## Step 2 — Disable Security Defaults

Source: [learn.microsoft.com — Disabling security defaults](https://learn.microsoft.com/entra/fundamentals/security-defaults#disabling-security-defaults).

Security Defaults is on by default for new tenants. It forces MFA on every sign-in, including ROPC. ROPC has no browser, so MFA prompts can't reach the user — every ROPC token request fails with `invalid_grant`. The fix is to disable Security Defaults.

For tenants on Entra ID P1+, you can use Conditional Access to require MFA only for the ZTAA app and leave ROPC alone. P1 is not required for the workshop.

1. Left-hand nav: **Entra ID** → **Overview**.
2. On the Overview page, look at the **tab strip across the top** (Overview, Monitoring, Properties, Recommendations, Tutorials). Click the **Properties** tab.
3. Scroll to the bottom of the Properties tab. Click **Manage security defaults** at the footer.
4. A side panel opens on the right. The first field is **Security defaults** with the value **Enabled**.
5. Change it to **Disabled (not recommended)**.
6. The panel asks you to pick a reason — choose **Other** (or any) with free-text "Cisco workshop ROPC requirement."
7. **Save**.

### Verify

Reload the Properties tab and click **Manage security defaults** again. The dropdown shows **Disabled**. Close the panel.

If your tenant has other production workloads, do not do this — set up a separate test tenant first.

## Step 3 — Add `rooez.com` as a custom domain

Source: [learn.microsoft.com — Add custom domain](https://learn.microsoft.com/entra/fundamentals/add-custom-domain).

Without this, you cannot create a user with a `@rooez.com` UPN. You'd be stuck with `<user>@<tenant>.onmicrosoft.com`, which doesn't match the demo's identity model.

### 3.1 — Add the domain in Entra

1. Left-hand nav: **Entra ID** → **Domain names**.
2. Click **+ Add custom domain** at the top.
3. Enter `rooez.com` → **Add domain**.

The domain's status page opens. It shows **Unverified** along with a TXT record value Microsoft generated:

| Record type | Alias | Value | TTL |
|---|---|---|---|
| TXT | @ | `MS=ms########` | 3600 |

Leave this Entra tab open.

### 3.2 — Add the TXT record at Cloudflare

1. Cloudflare dashboard for `rooez.com` → **DNS > Records**.
2. **+ Add record**.
3. Type: `TXT`. Name: `@`. Content: paste the entire `MS=ms########` value (including the `MS=` prefix). TTL: Auto. **Save**.

### 3.3 — Verify

Back in Entra, click **Verify** at the top of the `rooez.com` page. Cloudflare propagates fast (under a minute). If verification fails, wait 30 seconds and try again.

```bash
dig +short TXT rooez.com
```

Expected: a quoted string matching the `MS=ms########` value Microsoft showed you. Once Entra reports verified, you can leave the TXT record in Cloudflare or delete it.

## Step 4 — Create the demo user

Source: [learn.microsoft.com — How to create users](https://learn.microsoft.com/entra/fundamentals/how-to-create-delete-users#basics).

1. Left-hand nav: **Entra ID** → **Users**.
2. Top of the page → **+ New user** → **Create new user**.
3. **Basics** tab:
   - **User principal name**: `trader1` in the left textbox; pick `rooez.com` from the `@` dropdown.
   - **Mail nickname**: leave **Derive from user principal name** checked.
   - **Display name**: `Trader One`.
   - **Password**: leave **Auto-generate password** checked. Copy the value the wizard shows you on the review screen.
   - **Account enabled**: leave checked.
4. Skip the **Properties**, **Assignments**, and any other tabs.
5. Click **Review + create** → **Create**.

The wizard shows the autogenerated password in plain text on the confirmation screen. Copy it now — this is the only place it appears. trader1 will be forced to change it on first sign-in, but you need this temporary one to do that first sign-in.

### Verify

**Entra ID > Users** lists `trader1@rooez.com` with **Account enabled = Yes** and **User type = Member**.

## Step 5 — First sign-in and Microsoft Authenticator enrollment

Source: [learn.microsoft.com — Authenticator app registration via Security info](https://learn.microsoft.com/entra/identity/authentication/howto-authentication-passwordless-phone#guided-registration-with-my-sign-ins).

Two things happen here:

1. **trader1 sets a permanent password.** The auto-generated one is temporary; Microsoft requires a real one on first sign-in.
2. **Microsoft Authenticator gets registered.** Since Security Defaults is off, Microsoft won't force this — but ZTAA's SAML flow will request MFA, and the user needs the Authenticator factor on file. Better to register now in a controlled environment than during the workshop demo.

You need Microsoft Authenticator installed on your phone (App Store / Play Store) before starting.

### 5.1 — Open a private/incognito browser window

Use a separate window from your admin session, otherwise Microsoft will use your existing session and refuse to let you sign in as trader1.

- Chrome/Edge: Ctrl+Shift+N (Cmd+Shift+N on macOS)
- Firefox: Ctrl+Shift+P (Cmd+Shift+P on macOS)
- Safari: File → New Private Window

### 5.2 — Set the permanent password

1. Go to `https://login.microsoftonline.com`.
2. Username: `trader1@rooez.com` → **Next**.
3. Password: paste the temporary password → **Sign in**.
4. Microsoft prompts for an update:
   - Current password: temporary one.
   - New password: pick something strong, save in your password manager.
   - Confirm new password: same.
5. **Sign in**.

You land on a Microsoft 365 home or generic post-sign-in page. Don't close the window yet.

### 5.3 — Register Microsoft Authenticator

1. In the same private window, navigate to `https://aka.ms/mysecurityinfo` (redirects to `https://mysignins.microsoft.com/security-info`).
2. **+ Add sign-in method** → choose **Microsoft Authenticator** → **Add**.
3. Wizard says "Start by getting the app." Authenticator should already be on your phone → **Next**.
4. Wizard says "Set up your account" → **Next**. A QR code appears.
5. **On your phone:** open Authenticator → tap **+** (top right) → **Work or school account** → **Scan QR code** → point camera at the screen.
6. Phone shows the trader1 account in Authenticator.
7. Browser → **Next**. Microsoft sends a test push.
8. **Approve the test push** on your phone (you may need to enter a number shown in the browser).
9. Browser confirms registration succeeded.

### Verify

In the trader1 private window: `https://mysignins.microsoft.com/security-info` lists Microsoft Authenticator with the device name.

In the admin Entra portal: **Entra ID > Users > trader1@rooez.com > Authentication methods** shows Microsoft Authenticator.

Close the private window. This avoids any session interference with later testing.

## Step 6 — Create the ZTAA Enterprise App (SAML)

Source: [learn.microsoft.com — Create your own enterprise application](https://learn.microsoft.com/entra/identity/enterprise-apps/add-application-portal#create-your-own-application).

This is the SAML federation between FTDv and Entra. When a browser hits `trading.rooez.com/ztaa`, FTDv redirects to Entra, this app handles the auth, and Entra returns a signed assertion to FTDv.

A note on `ztaa-trading`: this is the Application Group name we'll reuse in cdFMC. Cisco docs use `[AppGroupName]` as a placeholder; we use `ztaa-trading` as the literal value. Wherever Cisco docs show `[AppGroupName]`, substitute `ztaa-trading`.

### 6.1 — Create the app shell

1. Left-hand nav: **Entra ID** → **Enterprise applications**.
2. Top of the page → **+ New application**.
3. **+ Create your own application** at the top of the gallery page.
4. Side panel:
   - Name: `RAVPN-ZTAA-Trading`.
   - Pick **Integrate any other application you don't find in the gallery (Non-gallery)**.
5. **Create** at the bottom.

You land on the app's overview after a few seconds.

### 6.2 — Configure SAML

1. Left sub-nav (under Manage) → **Single sign-on**.
2. **Select a single sign-on method** page → click the **SAML** tile.
3. You're on **Set up Single Sign-On with SAML** with five numbered sections.
4. Section 1, **Basic SAML Configuration** → click the pencil icon at top right of the card.
5. Fill in:

| Field | Value |
|---|---|
| Identifier (Entity ID) | `https://ztaa-trading.rooez.com` (set as default; remove any others) |
| Reply URL (Assertion Consumer Service URL) | `https://ztaa-trading.rooez.com/SAML/sso/login` (set as default; remove any others) |
| Sign on URL | `https://trading.rooez.com/ztaa` |

Leave Relay State and Logout Url blank.

6. **Save** at the top of the panel. If a "Test single sign-on with..." prompt appears, click **No, I'll test later**.

### 6.3 — Download the Federation Metadata XML

cdFMC consumes this file later when you create the SSO Server Object.

1. Scroll to section 3, **SAML Certificates**.
2. Find the **Federation Metadata XML** row → **Download**.
3. The file `RAVPN-ZTAA-Trading.xml` lands in your downloads folder.
4. Move it somewhere you'll find it later — a personal folder or password manager.

The repo's `.gitignore` covers this filename pattern, but the safer path is to store the XML outside the working directory entirely.

### 6.4 — Assign trader1

1. Left sub-nav → **Users and groups**.
2. **+ Add user/group** → **None Selected** → search for trader1 → click **Trader One** → **Select** → **Assign**.

### Verify

The app's Single sign-on page shows your three URLs in section 1 and a downloadable Federation Metadata XML in section 3. The Users and groups page lists Trader One. The XML on disk starts with `<?xml version="1.0" encoding="utf-8"?><EntityDescriptor ...`.

## Step 7 — Create the ISE App Registration (ROPC)

Source: [learn.microsoft.com — Configure app permissions](https://learn.microsoft.com/entra/identity-platform/quickstart-configure-app-access-web-apis) and [OAuth 2.0 ROPC flow](https://learn.microsoft.com/entra/identity-platform/v2-oauth-ropc).

This is the OAuth integration ISE uses to validate passwords against Entra. Five sub-steps and a verify.

### 7.1 — Create the registration

1. Left-hand nav: **Entra ID** → **App registrations**.
2. Top → **+ New registration**.
3. Name: `ISE-REST-ID-ROPC`. Supported account types: **Accounts in this organizational directory only (Single tenant)**. Redirect URI: leave blank.
4. **Register**.

You land on the app registration's Overview.

### 7.2 — Save the IDs

From the Overview page, copy:

- **Application (client) ID** — a GUID. ISE config calls this Client ID.
- **Directory (tenant) ID** — same tenant GUID we've used throughout.

### 7.3 — Enable public client flows

ROPC is classified as a public client flow even though we use a client secret.

1. Left sub-nav (under Manage) → **Authentication**.
2. Scroll to **Advanced settings** at the bottom.
3. **Allow public client flows** → **Yes**.
4. **Save** at the top.

### 7.4 — Add Microsoft Graph User.Read

ISE needs to read the user's profile after a successful auth.

1. Left sub-nav → **API permissions**.
2. **+ Add a permission** → **Microsoft Graph** → **Delegated permissions**.
3. Search for `User.Read`. Check it. **Add permissions**.
4. Back on the API permissions list, `User.Read` shows status **Not granted** (yellow warning).
5. At the top of the list, click **Grant admin consent for Default Directory** (or your tenant name) → **Yes**.
6. Status flips to **Granted for Default Directory** (green checkmark).

### 7.5 — Create a client secret

1. Left sub-nav → **Certificates & secrets**.
2. Make sure the **Client secrets** tab is selected.
3. **+ New client secret**.
4. Description: `ravpn-ise-secret`. Expires: 180 days (default).
5. **Add**.

A new row appears. Three columns are visible:

| Column | What it is | Use |
|---|---|---|
| Description | The label you typed | Identification |
| Value | The actual secret | This is what ISE configures as Client Secret |
| Secret ID | A separate GUID identifying the secret entry | **Not** the secret. Don't confuse the two. |

Click the copy icon next to **Value** and save it in your password manager **immediately**. Once you navigate away, the Value column shows only `*****`. There is no way to retrieve it later — if you lose it, delete this secret and create a new one.

### 7.6 — Verify with the ROPC curl test

This is the validation gate. If ROPC works at the curl level, ISE will work later.

```bash
TENANT_ID="<your tenant GUID>"
CLIENT_ID="<from step 7.2>"
CLIENT_SECRET="<from step 7.5>"
TRADER1_PASSWORD='<from step 5.2>'

curl -s -X POST "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
  -d "grant_type=password" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "username=trader1@rooez.com" \
  -d "password=${TRADER1_PASSWORD}" \
  -d "scope=https://graph.microsoft.com/.default" | python3 -m json.tool
```

**Use single quotes around the password.** Two reasons:

1. zsh expands `!` as history substitution inside double quotes. A password like `!Password1` triggers `zsh: event not found`.
2. Some terminals and pasted text replace straight quotes (`"`) with curly quotes (`"` `"`) automatically. Curly quotes are not valid shell quoting and zsh treats them as literal characters. Single quotes are safer.

**Expected:** JSON containing `token_type: "Bearer"`, `access_token`, `expires_in`, `scope` listing `User.Read`. That's success.

**Common errors:**

| Error | Likely cause |
|---|---|
| `invalid_grant` mentioning MFA or Conditional Access | Security Defaults still on, or trader1 has per-user MFA enforced. Re-check Step 2. |
| `unauthorized_client` | API permissions issue. Re-check Step 7.4 (admin-granted User.Read). |
| `invalid_client` | Client secret wrong. Confirm you copied the **Value**, not the **Secret ID**. |
| `zsh: event not found: ...` | The `!` in your password got expanded as history. Use single quotes. |

---

## What to save for ISE

| Field | Where |
|---|---|
| Tenant ID | App registration Overview, or `az account show --query tenantId -o tsv` |
| Client ID | App registration Overview (Application ID) |
| Client secret | Certificates & secrets, the **Value** column |
| trader1 password | The one you set in step 5.2 |
| Federation Metadata XML | Downloaded in step 6.3, saved outside the repo |

When the curl returns a token, the entire identity stack is verified. Move on to the cert generation step ([tls-certs.md](tls-certs.md)).
