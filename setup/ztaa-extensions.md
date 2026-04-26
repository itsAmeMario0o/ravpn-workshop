# Extending ZTAA to additional applications

The trading dashboard is the worked example for ZTAA in this build. The same pattern works for any internal HTTPS application you want to expose over zero-trust. This guide explains how to add a new one and which architecture to pick when you do.

ISE's admin GUI is the first add-on covered here. Bastion stays as the break-glass admin path. ZTAA becomes the daily-driver path for delegated admin access. Both work side by side.

## Two architectures

When the firewall acts as a zero-trust broker in front of a backend application, there are two ways to handle authentication. They both pass SAML and MFA through the firewall; they differ in what the backend application knows about the user.

### Option A. Gate-only

The firewall does SAML and MFA before traffic reaches the application. After the user passes the SAML challenge, the firewall opens a backend connection to the application. The application has no idea SAML happened. It still presents its own login page.

Result: the user signs in twice. Once at the firewall (Entra + MFA), once at the application (whatever the app expects locally).

### Option B. SAML pass-through (true SSO)

The firewall does SAML and MFA. The backend application is also configured for SAML against the same identity provider. The application accepts the SAML assertion the firewall passes through and signs the user in automatically.

Result: the user signs in once. Smooth.

## Which to pick

| Situation | Pick |
|---|---|
| The application supports SAML for its own login | **Option B**. Better experience, fewer passwords. |
| The application does not support SAML | **Option A**. There is no other choice. |
| The application supports SAML but you want minimal config changes | **Option A**. Faster to ship. |
| You are demoing zero-trust to a security audience | Either works; B is slicker on stage if SAML is well-rehearsed. |
| You are debugging a flaky integration | **Option A**. One fewer moving part. |

For the workshop demo, pick the approach that matches the audience and the time you have. **Option B is the better recommendation in production** because it removes a credential surface (the local app password) and gives the user a real SSO experience. Option A is the pragmatic choice when the backend cannot do SAML or when you want to ship fast.

## Adding a new ZTAA app: the generic flow

Same five steps regardless of which application you are protecting.

### 1. DNS

Create a Cloudflare A record for the new public hostname. Point it at the FTDv outside public IP. Gray cloud only — proxying breaks SAML callbacks.

Example: `ise.rooez.com` -> `${ftdv_outside_public_ip}`.

### 2. Cert

The wildcard identity cert (`*.rooez.com`) already covers any subdomain. No reissue needed. If you are using a non-wildcard cert, regenerate it with the new hostname added as a SAN.

### 3. Application Group in cdFMC

Go to the ZTAA application group flow in cdFMC and create a new group:

- Public-facing FQDN: the new hostname (e.g., `ise.rooez.com`).
- Backend address: the application's private IP and port (e.g., `https://10.100.4.10:443`).
- FTDv as the enforcement point.
- Bind the identity cert to the group.

### 4. SAML SSO Server Object

Reuse the existing one from the trading app, or create a new one with the same Federation Metadata XML from Entra. The Entity ID and ACS URL must contain the literal `[AppGroupName]` placeholder replaced by the real Application Group name. Same string in Entra and cdFMC. Mismatched strings break the redirect.

### 5. Application cert (backend trust)

The firewall needs to know how to trust the backend application's TLS cert. Two ways:

- **Upload the application's cert** as an Internal Cert at `Objects > Object Management > PKI > Internal Certs > Add`, then bind it to the protected app inside the application group.
- **Trust the application's existing cert** by uploading it as a CA in `Devices > Certificates > Manual + CA Only`. Use this when the application manages its own cert (like ISE does for its admin GUI).

### 6. Access policy

Add an FTD access control rule that permits FTD to reach the backend application's subnet on the right port. For ISE this is the inside-to-identity boundary on TCP 443.

That's it. Repeat for each new app.

## Worked example: ISE admin GUI behind ZTAA (Option A)

What the user experiences:

1. Browser to `https://ise.rooez.com`.
2. Firewall presents the wildcard cert. Browser is happy.
3. Firewall redirects to Entra. User signs in, completes MFA.
4. Firewall proxies the connection to ISE's GUI at `https://10.100.4.10:443`.
5. ISE shows its own login page. User signs in with `iseadmin` and the local ISE password.

Two logins. Acceptable for a delegated-admin use case where MFA at the front door is the security control and the local ISE login is just role check.

### Configuration

Apply the generic flow above with these values.

| Step | Value |
|---|---|
| Hostname | `ise.rooez.com` |
| Backend | `https://10.100.4.10:443` |
| Cert | wildcard `*.rooez.com` (no change) |
| App cert / backend trust | Upload ISE's self-signed admin cert as a trustpoint (`Devices > Certificates > Manual + CA Only`). ISE manages its own cert; we trust it but do not replace it. |
| FTD policy | Allow FTD inside-to-identity on TCP 443. |
| SAML SSO Server | Reuse the trading-app object, or create a parallel one. |
| Application Group | New group named `ise-gui`. Replace `[AppGroupName]` with `ise-gui` in the Entra ACS URL and the cdFMC SSO Server Object. |

### Verify

- [ ] `dig +short ise.rooez.com @1.1.1.1` returns the FTDv outside IP.
- [ ] Browser to `https://ise.rooez.com` loads cleanly with no cert warning.
- [ ] After Entra + MFA, the page shows the ISE login form.
- [ ] After signing in to ISE, the admin dashboard loads.
- [ ] Bastion still works (`scripts/bastion-tunnel.sh ise 50443`) as a parallel admin path.

### When to upgrade to Option B

If you want true SSO for ISE, configure ISE itself for SAML against the same Entra IdP. ISE 3.x supports SAML for admin access under **Administration > Identity Management > External Identity Sources > SAML Id Providers**. The SAML assertion passing through the firewall then signs the user in to ISE automatically. Skip the second login.

This is the recommended end-state for any application that supports SAML. The same upgrade path applies to any other app you ZTAA-enable later — start with Option A to prove the gate works, switch the backend to Option B when you have time.

## Things that will trip you up

- **Backend cert mismatch.** If the application's cert does not match the FQDN the firewall uses for the backend connection, the firewall rejects the handshake. Either upload the cert as a trustpoint or set the application group to skip strict CN matching.
- **The `[AppGroupName]` placeholder.** Same gotcha as the trading app. The string in Entra (Entity ID, ACS URL) and the string in cdFMC (SSO Server Object) must match exactly.
- **One SAML provider, many app groups.** You can attach the same SSO Server Object to multiple application groups. You only need one Federation Metadata XML download from Entra for the whole demo.
- **Wildcard cert and certificate transparency logs.** Wildcards still appear in CT logs. They just hide which specific subdomains exist behind them. If your security policy requires explicit per-host certs, drop the wildcard and add SANs explicitly.
