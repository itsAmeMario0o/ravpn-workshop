# Entra ID rotation (Python)

A single-file Python script that rotates one service account's password in Entra ID via the Microsoft Graph REST API.

## Files

- `rotate_entra_password.py` — the rotator.
- `requirements.txt` — Python dependencies (small list).

## Prerequisites

Python 3.10 or later. Earlier versions may work but aren't tested.

Install dependencies in a virtual environment so they don't conflict with system Python:

```bash
python3 -m venv .venv
source .venv/bin/activate   # (on Windows: .venv\Scripts\activate)
pip install -r requirements.txt
```

The script itself uses two libraries:

- `msal` — Microsoft's official auth library, handles the OAuth client credentials flow.
- `requests` — HTTP client.

No SDK. The Graph API is simple enough at this scope that direct REST is clearer than pulling in `msgraph-sdk`.

## Set the environment variables

```bash
export ENTRA_TENANT_ID="<tenant id GUID>"
export ENTRA_CLIENT_ID="<app registration client id>"
export ENTRA_CLIENT_SECRET="<app registration client secret>"
```

For longer-term use, drop these into a `.env` file (the workshop's `.gitignore` already excludes `.env*`) and source it:

```bash
set -a
source ../.env
set +a
```

## Run it

```bash
python rotate_entra_password.py --user svc-automation@rooez.com
```

What it does:

1. Generates a 32-character random password with at least one upper, lower, digit, and special character.
2. Acquires a Microsoft Graph token using the client credentials flow.
3. Calls `PATCH /users/{upn}` with the new `passwordProfile`.
4. Prints the new password to stdout (only once).
5. Exits with status `0` on success or `1` on any failure.

## Optional flags

| Flag | Default | Notes |
|---|---|---|
| `--length` | 32 | Password length. Minimum 12. |
| `--force-change` | not set | Sets `forceChangePasswordNextSignIn = true`. Don't use for service accounts. |
| `--verbose` | not set | Echoes each step to stderr for debugging. |

## Switching to certificate-based auth

The MSAL library supports certificate auth out of the box:

```python
app = msal.ConfidentialClientApplication(
    client_id,
    authority=f"https://login.microsoftonline.com/{tenant_id}",
    client_credential={
        "thumbprint": "<sha1 thumbprint>",
        "private_key": open("path/to/key.pem").read(),
    },
)
```

Replace the `client_credential=client_secret` line in the script with the dict form. No other changes needed.

## Hardening notes for production

- Pipe the new password into a vault rather than printing. The script's `main()` is structured so the print step is the last call, easy to swap.
- Wrap the Graph PATCH in a retry loop for `429` and `5xx` responses. `msal` already retries token acquisition.
- Run under a service identity (not a personal account) on a host that has its own access controls.
- Log to a structured destination (your SIEM) so rotations are auditable.
