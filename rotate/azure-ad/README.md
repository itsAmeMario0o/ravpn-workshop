# Entra ID service account password rotation

Two implementations live here, both doing the same thing in different ecosystems:

- `powershell/` — for shops that already run Microsoft.Graph PowerShell.
- `python/` — for shops with Python automation, CI runners, or cross-platform scheduling.

Pick whichever fits your existing tooling. The end result is identical: a Microsoft Graph API call that sets a new password on the target user.

## How Entra password rotation actually works under the hood

Microsoft Graph exposes a `PATCH /users/{id}` endpoint that accepts a `passwordProfile` object. The relevant fields are:

```json
{
  "passwordProfile": {
    "password": "<new password>",
    "forceChangePasswordNextSignIn": false
  }
}
```

For service accounts you set `forceChangePasswordNextSignIn` to `false` because there's no human to complete the password change at next sign-in. Setting it to `true` would lock the service account out the moment it tries to authenticate.

The caller needs the **`User.ReadWrite.All`** Graph permission. Two ways to get that:

| Caller type | Auth | Permission grant |
|---|---|---|
| Headless app (CI, scheduled job, automation) | App registration with client secret or certificate, client credentials flow | Application permission `User.ReadWrite.All`, admin-consented |
| Interactive admin run | Sign in as a privileged administrator | Delegated permission `User.ReadWrite.All` |

For real production use, **app-based auth with a certificate** is the recommended path — it's less prone to leakage than a client secret, and the cert can be rotated independently. The PoC scripts here show the client-secret flow because it's simpler to demonstrate; both scripts include a comment block on how to switch to certificate auth.

## App registration setup (one-time)

Whichever language you pick, the app registration is the same.

1. Sign in to the [Microsoft Entra admin center](https://entra.microsoft.com).
2. **Identity > Applications > App registrations > + New registration**.
3. Name: `password-rotator-svc`. Single tenant. No redirect URI.
4. After creation, save the **Application (client) ID** and **Directory (tenant) ID** from the Overview page.
5. **API permissions > + Add a permission > Microsoft Graph > Application permissions**. Tick **`User.ReadWrite.All`**. Click **Add permissions**, then **Grant admin consent**.
6. **Certificates & secrets > + New client secret**. Copy the **Value** column immediately.

You now have three values:

- Tenant ID
- Client ID
- Client secret

These three feed every example in this folder. Store them in your secret manager.

## What the scripts do not handle (yet)

These are PoCs. For a hardened production rotator you would also want:

- Push the new password into Azure Key Vault, AWS Secrets Manager, or HashiCorp Vault rather than printing it.
- Update every downstream consumer that needs the new password (CI variables, application configs, etc.). This is usually the longest part of a real rotation pipeline.
- Notify a Slack/Teams/PagerDuty channel on success or failure.
- Retry on transient Graph errors (`429 Too Many Requests`, `503 Service Unavailable`) with exponential backoff.
- Log to a structured destination (your SIEM) so rotations are auditable.
- Roll back the password on the IdP if downstream propagation fails.

The PoC code in each language subfolder leaves clear seams where these production additions slot in.
