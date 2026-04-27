# Cisco FMC / cdFMC password rotation

There is **no working REST API path** for rotating a local user password on Cisco FMC (Firepower Management Center) or cdFMC (cloud-delivered FMC). This folder is intentionally code-free; the README explains why and what to do instead.

## What we checked

The Cisco FMC REST API does expose a `/api/fmc_config/v1/domain/{domainUUID}/users` endpoint, and you can read user objects from it. But the password attribute is **write-only at user creation time** and **cannot be updated** after the user exists. There's no PATCH or PUT path that accepts a new password for an existing local user. This is consistent across FMC 6.x, 7.x, and the current cdFMC.

The same limitation applies to FTD when it's managed by FMC. FTD doesn't expose a separate user management API; user accounts on the device are administered through FMC, which inherits the same restriction.

## Where local user password changes actually happen

For FMC web UI users:

- **Web UI:** `System > Users > Users`. Edit the user, set a new password, save.
- **Configuration Guide:** [Cisco — User Accounts for FMC](https://www.cisco.com/c/en/us/td/docs/security/secure-firewall/management-center/admin/710/management-center-admin-71/system-users.html)

For the FMC CLI admin (a separate account from the web UI admin):

- **CLI command:** `configure password` from the FMC shell. Note that web UI and CLI admin passwords are tracked separately, so a rotation in one does not propagate to the other.

Neither of these is automatable via REST. You can drive the web UI with a browser-automation tool like Selenium or Playwright, but that's brittle and not what most environments mean by "API rotation."

## The recommended path

If you need to rotate the password for a service account that authenticates against FMC, **move the account to external authentication** instead of leaving it as a local user. FMC supports several external auth options:

- **LDAP / Active Directory** — point FMC at an LDAP/AD server. The service account lives in AD/Entra; rotation happens there using `../azure-ad/`.
- **RADIUS** — point FMC at a RADIUS server (commonly ISE in this kind of architecture). The service account credentials live where RADIUS gets them from, typically AD/Entra again.
- **SAML SSO** — for human admin access; not typically used for service accounts because it implies an interactive flow.

The configuration path in FMC: **System > Users > External Authentication**. Assign a role mapping so the external user gets the right FMC permissions when they sign in.

Once external auth is in place, the FMC has no copy of the password — it forwards every authentication request to the IdP. Rotating in the IdP (using the Entra rotator in `../azure-ad/`) is automatic from FMC's perspective; FMC just sees the next sign-in succeed with the new credential.

## When this might not be enough

A handful of FMC accounts can't be moved to external auth:

- The **CLI admin** account on the FMC virtual or hardware appliance. CLI access doesn't honor LDAP/RADIUS in most FMC versions.
- The **web UI emergency admin** if your policy requires a break-glass local account.

For these, manual rotation via the FMC GUI or CLI is the only path. Schedule them on your operational calendar (e.g., quarterly) and document the rotation in a runbook, since automation isn't available.

## Summary

| Scenario | Rotation path |
|---|---|
| FMC service account used by API automation | Move to LDAP/RADIUS, rotate the IdP account via `../azure-ad/` |
| FMC web UI human admin tied to AD | Already in IdP; rotate via `../azure-ad/` |
| FMC web UI break-glass local admin | Manual via GUI |
| FMC CLI admin | Manual via `configure password` |
| FTD local user | Same as FMC; managed through FMC |
