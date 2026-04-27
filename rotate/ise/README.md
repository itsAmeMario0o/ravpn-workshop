# Cisco ISE internal user password rotation

A Python script that rotates the password for an ISE **internal user** via the ERS (External RESTful Services) API.

## When to use this

Only when the account being rotated is **local to ISE** — that is, an internal admin or service account that ISE itself authenticates against its built-in user store, not against an external IdP.

For accounts that live in Entra ID, AD, or another external store and that ISE consults via REST ID / RADIUS-to-AD / similar, **do not use this script**. Rotate at the IdP instead (see `../azure-ad/`). ISE doesn't hold a copy of those passwords.

A common case where you'd use this script: ISE's built-in `ersapi` admin or a dedicated read-write service account used by your network automation tools. These accounts are tied to ISE itself; no external IdP is involved.

## Prerequisites

- ISE 3.x or newer with ERS enabled. The workshop deploy turns ERS on via the user_data field (`ersapi=yes`), so this is already true for the demo environment.
- An ISE admin user with the **External RESTful Services Admin** role (this is a separate role from the regular Super Admin; you grant it explicitly under Administration > System > Admin Access > Administrators > Admin Users). The script uses this admin to call the API.
- Network reachability to ISE on **TCP 9060** (the ERS port).

## Files

- `rotate_ise_internal_user.py` — the rotator.
- `requirements.txt` — Python dependencies.

## Set the environment variables

```bash
export ISE_HOST="10.100.4.10"             # or ISE FQDN if you have DNS
export ISE_ADMIN_USER="ers-admin"         # the ERS Admin role user
export ISE_ADMIN_PASSWORD="..."           # password for ers-admin
```

The host can be an IP or FQDN. The workshop's ISE listens on `10.100.4.10`. If you're running the rotator from your laptop you'll need a Bastion tunnel open to that address first (see `scripts/bastion-tunnel.sh ise 50443` in the main repo, then set `ISE_HOST=127.0.0.1:50443`).

## Run it

```bash
python rotate_ise_internal_user.py --target svc-automation
```

What it does:

1. Builds an HTTPS session with HTTP Basic auth and the ERS-required `Accept`/`Content-Type` JSON headers.
2. Looks up the target user by username via `GET /ers/config/internaluser/name/{name}`.
3. Generates a 32-character random password matching ISE complexity rules (upper + lower + digit + special, ≥ 6 chars).
4. Calls `PUT /ers/config/internaluser/{id}` with a body that updates only the password fields.
5. Prints the new password to stdout once.

## Optional flags

| Flag | Default | Notes |
|---|---|---|
| `--length` | 32 | Password length. ISE allows 6+, default is intentionally generous. |
| `--also-enable-password` | not set | Sets the same value for the optional `enablePassword` field. |
| `--insecure` | not set | Skip TLS verification. **Demo only.** ISE ships with a self-signed cert; use this flag against an unmanaged-cert ISE. In production, install a proper cert chain on ISE and trust it. |
| `--verbose` | not set | Log each step to stderr. |

## What this does NOT cover

- It does not push the new password to wherever your automation reads from. That handoff is yours.
- It does not rotate ISE Super Admin or CLI admin passwords. Those use different mechanisms (Super Admin via the GUI, CLI via the `password` command). Both are out of scope for ERS.
- It does not roll back on failure. If the PUT succeeds but your downstream consumer can't get the new value, the old password is gone and you'll need to rotate again.

## Production hardening

The PoC structure leaves clear seams for these:

- Pipe the new password into Azure Key Vault, AWS Secrets Manager, or HashiCorp Vault rather than printing.
- Wrap the PUT in retry-on-5xx logic with exponential backoff.
- Use TLS verification with a proper ISE cert. The `--insecure` flag exists for demo convenience only.
- Run from a controlled host (CI runner with restricted IAM, a hardened jump host, etc.) and log to your SIEM.

## API references

- [Cisco ISE 3.x REST API documentation](https://developer.cisco.com/docs/identity-services-engine/latest/)
- [ISE ERS API guide — Internal Users](https://developer.cisco.com/docs/identity-services-engine/latest/internal-user/)
