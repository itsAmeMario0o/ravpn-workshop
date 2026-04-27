# Entra ID rotation (PowerShell)

A single PowerShell script that rotates one service account's password in Entra ID.

## Files

- `Rotate-EntraServiceAccountPassword.ps1` — the rotator.

## Prerequisites

PowerShell 7+ on Windows, macOS, or Linux. Older Windows PowerShell 5.1 also works but is not recommended.

The Microsoft.Graph SDK module:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Repository PSGallery
```

The first install pulls in a large module set. ~2 minutes on a fast connection.

## Set the environment variables

The script reads the app registration credentials from environment variables so nothing sensitive lives in source:

```powershell
$env:ENTRA_TENANT_ID     = "<your tenant id GUID>"
$env:ENTRA_CLIENT_ID     = "<your app registration client id>"
$env:ENTRA_CLIENT_SECRET = "<your app registration client secret>"
```

Alternatively, set them in your shell profile or in a CI runner's secret store.

## Run it

```powershell
./Rotate-EntraServiceAccountPassword.ps1 -UserPrincipalName "svc-automation@rooez.com"
```

What it does:

1. Generates a 32-character random password with at least one upper, lower, digit, and special character.
2. Acquires a Graph token using the client credentials flow.
3. Calls `PATCH /users/{upn}` with the new `passwordProfile`.
4. Prints the new password to stdout (only once — capture it now).
5. Exits with code `0` on success or `1` on any failure.

## Optional parameters

| Parameter | Default | Notes |
|---|---|---|
| `-PasswordLength` | 32 | Generated password length. Minimum 12 for any reasonable security; default is 32. |
| `-ForceChangeAtNextSignIn` | `$false` | Leave at false for service accounts. Setting to `$true` locks out a non-interactive caller. |

## Switching to certificate-based auth

Client secrets are simpler but weaker than certificates. For production rotations:

1. Generate a self-signed cert and upload the public key to the app registration under **Certificates & secrets > Certificates**.
2. Replace the `$env:ENTRA_CLIENT_SECRET` use in the script with `Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumb`.

The script is structured so this swap is one block.

## Verify it worked

After running, sign in to Entra (or run a curl ROPC test like the workshop does for `trader1`) using the new password. If the credential works and the old one doesn't, rotation succeeded.
