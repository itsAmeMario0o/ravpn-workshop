# Cisco FMC / cdFMC password rotation

There is **no working REST API path** for rotating a local user password on Cisco FMC (Firepower Management Center) or cdFMC (cloud-delivered FMC). This folder is intentionally code-free; the README explains why and what to do instead.

## What we checked

The Cisco FMC REST API does expose a `/api/fmc_config/v1/domain/{domainUUID}/users` endpoint, and you can read user objects from it. But the password attribute is **write-only at user creation time** and **cannot be updated** after the user exists. There's no PATCH or PUT path that accepts a new password for an existing local user. This is consistent across FMC 6.x, 7.x, and the current cdFMC.

The same limitation applies to FTD when it's managed by FMC. FTD doesn't expose a separate user management API; user accounts on the device are administered through FMC, which inherits the same restriction.

## Where local user password changes actually happen

For FMC web UI users:

- **Web UI:** `System > Users > Users`. Edit the user, set a new password, save.
- **Configuration Guide:** [Cisco — User Accounts for FMC](https://www.cisco.com/c/en/us/td/docs/security/secure-firewall/management-center/admin/710/management-center-admin-71/system-users.html)

For the **default built-in `admin`** CLI user:

- **CLI command:** `configure password` from the FMC shell. The default `admin` cannot be moved to external authentication — it's hardcoded as a local account. Web UI and CLI admin passwords are tracked separately, so rotating one does not propagate to the other.

Neither web UI nor CLI for the default `admin` is automatable via REST.

For **additional CLI users beyond the default `admin`**, FMC does support external authentication for shell access via LDAP or RADIUS. This is often missed because most documentation focuses on the default admin behavior. Specifically:

- **LDAP for CLI access** uses a search filter on the External Authentication object to identify which LDAP users get shell access.
- **RADIUS for CLI access** requires you to pre-list the eligible usernames in the External Authentication object (RADIUS doesn't have a directory you can query, so FMC needs the explicit list).
- Only one External Authentication object can be designated for CLI/shell at a time, even though multiple objects can serve the web UI.
- The shell-access CLI users land on FMC's restricted shell. From there, the `expert` command escalates to a full Linux shell, which is why this is a sensitive privilege; review the role mapping carefully.

Once external auth is configured for CLI, those users' passwords live in the external IdP and rotation happens there using `../azure-ad/`. **The default `admin` is the only CLI account that genuinely has to be rotated manually.**

## The recommended path

If you need to rotate the password for a service account that authenticates against FMC, **move the account to external authentication** instead of leaving it as a local user. FMC supports several external auth options:

- **LDAP / Active Directory** — point FMC at an LDAP/AD server. The service account lives in AD/Entra; rotation happens there using `../azure-ad/`.
- **RADIUS** — point FMC at a RADIUS server (commonly ISE in this kind of architecture). The service account credentials live where RADIUS gets them from, typically AD/Entra again.
- **SAML SSO** — for human admin access; not typically used for service accounts because it implies an interactive flow.

The configuration path in FMC: **System > Users > External Authentication**. Assign a role mapping so the external user gets the right FMC permissions when they sign in.

Once external auth is in place, the FMC has no copy of the password — it forwards every authentication request to the IdP. Rotating in the IdP (using the Entra rotator in `../azure-ad/`) is automatic from FMC's perspective; FMC just sees the next sign-in succeed with the new credential.

## When this might not be enough

A small number of FMC accounts genuinely can't be moved to external auth:

- The **default built-in `admin`** account, both web UI side and CLI side. These are always local; they can't be migrated to LDAP/RADIUS/SAML in any FMC version.
- The **web UI emergency admin** if your policy requires a separate break-glass local account.

For these, manual rotation via the FMC GUI (`System > Users > Users`) or CLI (`configure password`) is the only path. Schedule them on your operational calendar (e.g., quarterly) and document the rotation in a runbook, since automation isn't available.

**Other CLI users** (not the default admin) can be external. If your operational pattern is "everyone who SSHes to FMC has a personal account in AD or RADIUS," that's supported and rotation lives in the IdP via `../azure-ad/`. The key is configuring the External Authentication object with the right CLI-access settings (LDAP filter or RADIUS user list).

## Summary

| Scenario | Rotation path |
|---|---|
| FMC service account used by API automation | Move to LDAP/RADIUS for web access, rotate the IdP account via `../azure-ad/` |
| FMC web UI human admin tied to AD | Already in IdP; rotate via `../azure-ad/` |
| FMC web UI break-glass local admin | Manual via GUI |
| **FMC default built-in `admin` (web)** | Manual via GUI — cannot be made external |
| **FMC default built-in `admin` (CLI)** | Manual via `configure password` — cannot be made external |
| **Additional FMC CLI users (not the default admin)** | LDAP filter or RADIUS user list, then rotate the IdP account via `../azure-ad/` |
| FTD local user | Same as FMC; managed through FMC |
