# Service account password rotation

Service accounts are accounts used by automation, scripts, integrations, and other non-human consumers to authenticate against a system. They differ from human accounts in two important ways:

1. They have no human attached, so they cannot complete an MFA prompt.
2. Their credentials are stored in config files, secret stores, or environment variables — places where a leaked credential can sit unnoticed for a long time.

The defense against the second risk is **regular password rotation**: change the credential on a schedule, update every consumer that needs it, retire the old value. A monthly rotation cadence is common.

This folder is a set of working proofs of concept for rotating service account passwords across the platforms in this workshop. Each subfolder is self-contained: README, code, and (where applicable) dependencies.

## What's here

```
rotate/
├── azure-ad/            Entra ID (Azure AD) service accounts
│   ├── powershell/      PowerShell via the Microsoft.Graph SDK
│   └── python/          Python via Microsoft Graph REST + MSAL
├── ise/                 Cisco ISE internal admin users via ERS API (Python)
└── fmc/                 Cisco FMC / cdFMC — see the README inside
```

## Which one applies?

The right tool depends on where the service account actually lives.

| Account lives in | Use |
|---|---|
| Entra ID (most common when ISE/FMC use external auth) | `azure-ad/` |
| ISE local user store | `ise/` |
| FMC / cdFMC local user store | See `fmc/README.md` — REST API path is not available; rotation is GUI-only or CLI-only on FMC. The recommended fix is to move the account to external auth (LDAP, RADIUS, SAML) so rotation happens in the IdP. |
| FTD local user store | Same as FMC — managed through FMC, no direct API path |

## Why this matters in this demo

In this workshop, the demo identity flows look like this:

- **RAVPN authentication.** The user signs in via Cisco Secure Client. ISE forwards the credentials to Entra ID via the ROPC flow. Entra is the source of truth for the user's password. **ISE has no copy of the password.** When that user's password rotates in Entra, ISE just sees the next sign-in succeed with the new value — no ISE config change needed.
- **ZTAA authentication.** The browser hits the firewall, the firewall redirects to Entra for SAML, the user signs in there. Same story — Entra holds the password.

So if your service accounts go through the same identity store the workshop uses, you only need the Entra ID rotation path. The ISE-local rotation only applies if you're rotating credentials for someone like the `ersapi` admin used by your own automation against ISE itself.

## Common patterns across all the rotators

Each script in this folder follows the same shape:

1. Read configuration (target account, secret store details, auth credentials) from environment variables or a config file. Nothing sensitive in source.
2. Authenticate to the target platform.
3. Generate a strong random password matching the platform's complexity requirements.
4. Set the new password via the platform's API.
5. Hand the new password off — print it (for testing), write it to a vault, or push it to your config management system.
6. Exit with a clean status code so a scheduler can act on success or failure.

The scripts are PoC quality: they work, they're commented, and they're a starting point. For production use you would add things like Key Vault integration for the new password, retry logic, structured logging to a SIEM, and a notification on failure. The README in each subfolder calls out specific production hardening notes.
