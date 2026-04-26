# Azure FTDv RAVPN Demo Environment — Plan

_Last updated: 2026-04-24_
_Status: Planning. No resources deployed._
_Sources: FTDv Getting Started Guide (7.2 and earlier), Azure FTDv deployment guide, FMC admin guide, FTD RAVPN admin guide, Microsoft Learn (Dv2 series, NVA docs, Accelerated Networking), internal NGVPN HLD and LLD references_

---

## Purpose

Single FTDv in Azure, pre-registered to cdFMC through Security Cloud Control. All ancillary infrastructure (VNet, subnets, NSGs, ISEv, web apps) is pre-built and configured before the demo. The live demo focuses on FTD configuration within cdFMC. Identity source is Microsoft Entra ID for both RAVPN (via ISE RADIUS with REST ID/ROPC) and ZTAA (via SAML direct). No on-prem AD DC or IdP VM required.

Demo scope:

1. Remote Access VPN (RAVPN) with Secure Client, authenticating through ISE (RADIUS) backed by Entra ID (REST ID/ROPC), connecting to a fictitious trading dashboard app
2. Zero Trust Application Access (ZTAA) with SAML authentication through Microsoft Entra ID + MFA (Microsoft Authenticator), accessing a second trading dashboard app (different color scheme, same layout)
3. cdFMC VPN dashboard: real-time session monitoring, connection analytics, tunnel status
4. Geolocation VPN: policy-based tunnel steering by client geographic location
5. Multi-instance introduction: conceptual overview of FTD multi-instance on Firepower 4200 for workload isolation (not deployed in this demo, presented as a future use case for multi-tenant VPN architectures)

This environment supports the PoV workshop (Section 4: RAVPN primitives, Section 5: SAML, Section 6: Geolocation VPN, Section 7: ZTAA, Section 9: Automation/ZTP).

### Demo assumptions

All infrastructure is provisioned through Terraform (`azurerm` provider). Identity is fully in Entra ID (no on-prem AD DC). ISE authenticates RAVPN users against Entra via REST ID (ROPC). ZTAA authenticates directly via Entra SAML. The FTDv is already registered in cdFMC before the live demo begins. The audience sees FTD policy configuration, deployment, and validation only.

---

## Architecture (single-site demo)

```
Internet
   │
   ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Azure VNet: 10.100.0.0/16                                          │
│                                                                      │
│  ┌──────────────────┐                                                │
│  │  FTDv (Demo)     │                                                │
│  │  Standard_D8s_v3 │                                                │
│  │  8 vCPU / 32 GB  │                                                │
│  │  FTDv5 tier      │                                                │
│  │                  │                                                │
│  │  Nic0: mgmt      │  10.100.0.10                                   │
│  │  Nic1: diag      │  10.100.1.10                                   │
│  │  Nic2: outside   │  10.100.2.10  ← pip-ftdv-outside (RAVPN)      │
│  │  Nic3: inside    │  10.100.3.10                                   │
│  └────────┬─────────┘                                                │
│           │ Inside (10.100.3.0/24)                                   │
│           ▼                                                          │
│  ┌────────────────┐                      Identity: Microsoft       │
│  │ Trading App    │                      Entra ID (SaaS, no VM)    │
│  │ Ubuntu B1s     │                      + Microsoft Authenticator │
│  │ 10.100.3.20    │                      for MFA                   │
│  │ React/Vite     │                                                │
│  │ Trading dash   │                      RAVPN: FTD > ISE > Entra  │
│  │ /vpn (dark)    │                      ZTAA:  FTD > Entra SAML   │
│  │ /ztaa (light)  │                                                │
│  └────────────────┘                                                │
│                                                                      │
│                                          ┌──────────────────┐       │
│                                          │ ISEv             │       │
│                                          │ Extra Small      │       │
│                                          │ Standard_D8s_v4  │       │
│                                          │ 8 vCPU / 32 GB   │       │
│                                          │ 10.100.4.10      │       │
│                                          │ PSN-only node    │       │
│                                          │ REST ID > Entra  │       │
│                                          │ identity subnet  │       │
│                                          │ 10.100.4.0/24    │       │
│                                          └──────────────────┘       │
└──────────────────────────────────────────────────────────────────────┘
         │ Management (Nic0, 10.100.0.0/24)
         ▼
   cdFMC via Security Cloud Control
   (SaaS, FTDv pre-registered before demo)
```

---

## Azure resource requirements

### Virtual Network

| Subnet | CIDR | Purpose |
|---|---|---|
| management | 10.100.0.0/24 | FTDv management interface (Nic0). cdFMC communication over TCP 8305. SSH/HTTPS admin access. |
| diagnostic | 10.100.1.0/24 | FTDv diagnostic interface (Nic1). Optional but recommended. |
| outside | 10.100.2.0/24 | FTDv outside interface (Nic2). RAVPN termination. Public IP attached here. |
| inside | 10.100.3.0/24 | FTDv inside interface (Nic3). Protected resources: VPN app, ZTAA app. |
| identity | 10.100.4.0/24 | ISEv PSN node (optional). Separated from inside for realistic segmentation. |

### Interface mapping (Azure NIC to FTD interface)

This order is fixed by the FTDv image. You cannot remap NICs to different FTD interfaces.

| Azure NIC | FTD Interface | Subnet | Purpose |
|---|---|---|---|
| Nic0 | Management | management | cdFMC sftunnel (TCP 8305), SSH, HTTPS admin |
| Nic1 | GigabitEthernet0/0 | diagnostic | Diagnostic traffic. Can be disabled with `"Diagnostic": "OFF"` in Custom Data. |
| Nic2 | GigabitEthernet0/1 | outside | RAVPN termination. Public IP here. |
| Nic3 | GigabitEthernet0/2 | inside | Protected resources. VPN app, ZTAA app. |

Larger VM sizes support up to 8 NICs total. For this demo, 4 is sufficient.

[from notebook source: FTDv Getting Started Guide 7.2]

### Network Security Groups

NSGs are required when using Standard SKU public IPs (Azure enforces this).

| NSG | Subnet | Inbound rules |
|---|---|---|
| nsg-mgmt | management | TCP 22 (SSH), TCP 443 (HTTPS), TCP 8305 (FMC sftunnel) from your IP + cdFMC ranges |
| nsg-outside | outside | TCP 443 (SSL VPN), UDP 443 (DTLS), UDP 500 + 4500 (IKEv2 if needed) from any |
| nsg-inside | inside | Allow all from 10.100.0.0/16 (internal). TCP 443 (trading app at .3.20) from 10.100.0.0/16. |
| nsg-identity | identity | UDP 1812/1813 (RADIUS), TCP 49 (TACACS+), TCP 443 (ISE admin), TCP 8443 (ISE portal), UDP 1700 (CoA) from 10.100.0.0/16. TCP 22/443 from your IP. |
| nsg-diag | diagnostic | TCP 22 from your IP (optional) |

[from web: Microsoft Learn NVA troubleshooting guide]

### Compute

**FTD 10.0 drops the Dv2 VM family.** Standard_D3_v2 and Standard_D4_v2 are listed for 7.7 and below only. For 10.x, use Dsv3 or Fsv2 families.

| Resource | Spec | Subnet | IP | Notes |
|---|---|---|---|---|
| FTDv | Standard_D8s_v3, 8 vCPU, 32 GB RAM | mgmt/diag/outside/inside | .0.10/.1.10/.2.10/.3.10 | FTDv5 or FTDv10 tier. Smallest 10.x-compatible size. |
| Trading App | Standard_B1s (Ubuntu 22.04) | inside | 10.100.3.20 | React/Vite SPA. Fictitious financial trading dashboard. Single app, two color themes by route: `/vpn` (dark) for RAVPN demo, `/ztaa` (light) for ZTAA demo. Nginx serves static build. Inspiration: https://github.com/galafis/trading-dashboard |
| ISEv | Standard_D8s_v4, 8 vCPU, 32 GB RAM | identity | 10.100.4.10 | ISE 3.5 Extra Small (PSNLite), PSN-only. 300 GB disk. Native Azure IaaS, supported since ISE 3.2. Identity source: Entra ID via REST ID (ROPC). |

Supported Azure VM sizes for FTD 10.x:

| VM Size | vCPU | RAM | Max NICs | Performance Tier | Notes |
|---|---|---|---|---|---|
| Standard_D8s_v3 | 8 | 32 GB | 4 | FTDv5/10/20/30 | Recommended for demo. Smallest 10.x option. |
| Standard_D16s_v3 | 16 | 64 GB | 8 | FTDv50/100/U(32) | Production-grade. |
| Standard_F8s_v2 | 8 | 16 GB | 4 | FTDv5/10/20 | Compute-optimized, lower RAM. |
| Standard_F16s_v2 | 16 | 32 GB | 8 | FTDv50/100 | Compute-optimized, higher core count. |

Dv2 family (7.7 and below only, NOT for 10.x):

| VM Size | vCPU | RAM | Max NICs | FTD Version |
|---|---|---|---|---|
| Standard_D3_v2 | 4 | 14 GB | 4 | 7.7 and below |
| Standard_D4_v2 | 8 | 28 GB | 8 | 6.5 to 7.7 |

[from notebook source: FTDv Getting Started Guide 7.2, FMC Device Config Guide 10.0]

### Performance tier reference

| Tier | Throughput | RAVPN Sessions | Min Resources |
|---|---|---|---|
| FTDv5 | 100 Mbps | 50 | 4 vCPU / 8 GB |
| FTDv10 | 1 Gbps | 250 | 4 vCPU / 8 GB |
| FTDv20 | 3 Gbps | 250 | 4 vCPU / 8 GB |
| FTDv30 | 5 Gbps | 250 | 8 vCPU / 16 GB |
| FTDv50 | 10 Gbps | 750 | 12 vCPU / 24 GB |
| FTDv100 | 16 Gbps | 10,000 | 16 vCPU / 32 GB |
| FTDvU (32-core) | Unlimited | 20,000 | 32 vCPU / 64 GB |
| FTDvU (64-core) | Unlimited | 32,000 | 64 vCPU / 128 GB |

FTDvU is new in 10.0. No software rate limiter. For this demo, FTDv5 or FTDv10 is sufficient.

FTDv 10.0 raises the max supported resources from 16 vCPU / 32 GB (7.x) to 64 vCPU / 128 GB.

[from notebook source: FMC Device Config Guide 10.0, FTDv Getting Started Guide 7.2]

### Public IPs

| Name | Attached to | Purpose |
|---|---|---|
| pip-ftdv-mgmt | FTDv Nic0 | SSH/HTTPS admin access, cdFMC registration |
| pip-ftdv-outside | FTDv Nic2 | RAVPN termination endpoint (Secure Client connects here) |

### NVA-specific Azure requirements

These apply to any third-party network virtual appliance on Azure, including FTDv.

| Requirement | Detail | Source |
|---|---|---|
| IP forwarding | Must be enabled on all data-plane NICs (Nic1, Nic2, Nic3). Azure drops packets where dest IP does not match NIC IP unless forwarding is on. | [from web: Microsoft Learn NVA guide] |
| Accelerated Networking | Supported on FTDv but disabled by default. Must stop/deallocate VM to enable. Enables SR-IOV bypass of host virtual switch for lower latency. | [from web: Microsoft Learn Accelerated Networking, from notebook source: FTDv Getting Started Guide 7.2] |
| VM Generation | Gen 1 only. Gen 2 is not supported. | [from notebook source: FTDv Getting Started Guide 7.2] |
| User-defined routes (UDRs) | Required on inside subnet to route return traffic through FTDv instead of Azure's default gateway. | [from web: Microsoft Learn virtual appliance scenario] |

### Marketplace image

Search Azure Marketplace for "Cisco Secure Firewall Threat Defense Virtual" or legacy name "Cisco Firepower NGFW Virtual (FTDv)." Two plans available: BYOL and PAYG.

PAYG licensing note: all features (Malware, Threat, URL Filtering, VPN) enabled by default, but PAYG is only supported when managed by FMC (not FDM). Works for our cdFMC scenario. No Cisco Smart Account needed for PAYG.

BYOL licensing note: requires Cisco Smart Account with export-controlled features (strong encryption) enabled for RAVPN. More cost-effective long-term. Required for clustering (not relevant here).

For this demo, target FTD 10.x (aligns with Mario's version decision and workshop context). ZTAA requires 7.4+, met by 10.x. Verify Marketplace image availability for 10.0.x at deploy time.

[from notebook source: FTDv Getting Started Guide 7.2, Azure FTDv deployment guide]

---

## Day-0 bootstrap (Custom Data)

JSON payload passed via the Azure VM Custom Data field during deployment:

```json
{
  "AdminPassword": "<strong-password>",
  "Hostname": "ftdv-demo",
  "FirewallMode": "Routed",
  "ManageLocally": "No",
  "FmcIpAddress": "DONTRESOLVE",
  "FmcRegKey": "<registration-key-from-SCC>",
  "FmcNatId": "<nat-id-from-SCC>",
  "Diagnostic": "OFF"
}
```

Parameter notes:
- `DONTRESOLVE`: required because cdFMC is not a directly addressable IP. Registration key and NAT ID are generated by Security Cloud Control.
- `Diagnostic`: set to `OFF` to skip the legacy diagnostic interface. Frees Nic1 (Gi0/0) for data traffic if needed. Optional.
- Admin username: set during Marketplace wizard. Cannot be "admin" (Azure restriction).
- Auth method: password or SSH public key (SSH recommended for demo).
- Console password recovery is not possible on Azure (no real-time serial console at boot). Do not lose the admin password.
- Azure "reset password" portal function is not supported for FTDv.

[from notebook source: FTDv Getting Started Guide 7.2, Azure FTDv deployment guide]

---

## cdFMC registration process

1. Log into Security Cloud Control (formerly Cisco Defense Orchestrator).
2. Navigate to cdFMC inventory. Add a new device.
3. SCC generates a `configure manager add` command with the cloud endpoint, registration key, and NAT ID.
4. SSH into the FTDv management IP.
5. Paste the generated command:
   ```
   configure manager add <cloud-endpoint> <reg-key> <nat-id>
   ```
6. Wait for sftunnel to establish (TLS-encrypted, TCP 8305). Heartbeat verification takes up to 2 minutes.
7. Device appears in cdFMC inventory. Deploy initial access control policy.

Key difference from on-prem FMC: SCC generates the full command. You do not manually define the registration key on both sides. SCC orchestrates the trust establishment.

[from notebook source: FMC admin guide, device config guide]

---

## RAVPN demo configuration checklist

After FTDv is registered and initial policy deployed:

| Step | What | Details |
|---|---|---|
| 1 | Smart License | Ensure RAVPN (AnyConnect) license entitlement is active. BYOL requires manual entitlement in Smart Account. PAYG includes it. |
| 2 | Identity certificate | SSL certificate for the outside interface (Secure Client TLS handshake). Options: (a) Let's Encrypt cert for `vpn.rooez.com` via DNS-01/Cloudflare (clean, no warnings), or (b) self-signed (Secure Client warns on first connect, then trusts). See "TLS certificate generation" section. |
| 3 | Secure Client package | Upload .pkg web-deploy image to cdFMC. Objects > Object Management > VPN > AnyConnect File. Pre-deploy images do not work. |
| 4 | Address pool | Create an IPv4 address pool for VPN clients (e.g., 10.100.200.0/24). |
| 5 | Authentication | ISE as RADIUS server. ISE authenticates against Entra ID via REST ID (ROPC). FTD sends RADIUS to ISE, ISE validates credentials against Entra, returns RADIUS Accept with authorization attributes. Mirrors common production auth models (FTD > ISE > identity source). |
| 6 | Connection profile | Use the RAVPN wizard in cdFMC. Assigns: Secure Client image, group policy, address pool, auth method, certificate, interface. |
| 7 | Group policy | Define split-tunnel or full-tunnel, DNS servers, default domain, banner. |
| 8 | NAT exemption | Exempt VPN pool from outbound NAT (inside source to VPN pool). Or use `sysopt permit-vpn` to bypass ACL for decrypted traffic. |
| 9 | Deploy and test | Deploy policy from cdFMC. Connect with Secure Client from a laptop. Verify tunnel, IP assignment, access to VPN trading dashboard app (10.100.3.20). |

[from notebook source: FTD RAVPN admin guide, FMC admin guide]

---

## ZTAA demo configuration checklist

Requirements: FTD 7.4+, Snort 3, routed mode. All met by this demo environment.

| Step | What | Details |
|---|---|---|
| 1 | SAML IdP (Entra ID) | Create Enterprise App in Entra, configure SAML SSO, enable MFA with Microsoft Authenticator. Entity ID: `https://trading.rooez.com/[AppGroupName]/saml/sp/metadata`. ACS URL: `https://trading.rooez.com/[AppGroupName]/+CSCOE+/saml/sp/acs?tgname=[AppGroupName]`. See `outputs/ztaa-demo-notes.md` for full steps. |
| 2 | IdP metadata | From Entra: download Federation Metadata XML. Contains Entity ID, SSO URL, signing certificate. |
| 3 | SSO Server Object | In cdFMC: Objects > AAA Server > Single Sign-On Server. Upload Entra signing cert, enter Entra IdP URLs from metadata. |
| 4a | Identity/proxy certificate | Wildcard or SAN cert matching all published app FQDNs (`trading.rooez.com`). FTD presents this to the browser during pre-authentication. Let's Encrypt recommended. |
| 4b | Application certificate | Per-app cert + private key for the backend app (10.100.3.20). Import into cdFMC as PKI object. Enables TLS decryption (known key method) for Snort 3 inspection. |
| 5 | Application object | Create an Application object pointing to the ZTAA app (10.100.3.21, port 443). |
| 6 | ZTA policy | Create a Zero Trust Application Policy in cdFMC. One policy per FTD. |
| 7 | Policy rules | Map SAML-authenticated users/groups to the application object. |
| 8 | Deploy and test | Deploy. Open browser, navigate to the application URL. FTD intercepts, redirects to Entra, user authenticates + MFA push, FTD validates assertion, brokers connection. No VPN client needed. |

ZTAA key points for the workshop:
- SAML-only authentication. No RADIUS, no LDAP.
- MFA enforced upstream in Entra (Microsoft Authenticator push).
- Eliminates RADIUS for post-logon app access (aligns with modern IAM direction).
- FTD is the enforcement point. IdP is Entra ID (cloud), but on-prem IdPs also supported.
- Per-app scoped access. Authenticating to one app does not grant access to others.
- FTD performs TLS decryption and applies IPS/malware inspection to the brokered traffic.

[from notebook source: FTD RAVPN admin guide, FMC admin guide]

---

## DNS and domain configuration

### Public DNS (Cloudflare, rooez.com)

ZTAA requires a public hostname. FTD must present a valid TLS cert matching the hostname the browser connects to. SAML Entity ID, Reply URL, and FTD portal URL must all use the same hostname.

| Record | Type | Name | Value | Proxy |
|---|---|---|---|---|
| ZTAA app entry point | A | trading | FTD public IP (pip-ftdv-outside) | DNS only (gray cloud) |
| RAVPN entry point | A | vpn | FTD public IP (pip-ftdv-outside) | DNS only (gray cloud) |

Result: `trading.rooez.com` and `vpn.rooez.com` both resolve to FTD outside public IP. Same IP, two hostnames. FTD differentiates by SNI/connection profile.

Keep Cloudflare proxy off (gray cloud). Orange cloud introduces TLS termination at Cloudflare and can break SAML redirects.

### Entra custom domain (rooez.com)

The Entra tenant primary domain is the tenant's default `<tenant>.onmicrosoft.com` (or whichever custom domain is already verified on it). To create users with `@rooez.com` UPNs, add and verify `rooez.com` as a custom domain.

1. Entra > Custom domain names > Add domain > enter `rooez.com`.
2. Entra provides a TXT record value. Add it in Cloudflare: Type TXT, Name `@`, Value from Entra.
3. Wait 1-5 minutes, then verify in Entra.
4. After verification, create `trader1@rooez.com`. No license required.

Constraint: a domain can only belong to one Entra tenant at a time. If `rooez.com` was previously verified in another tenant, remove it there first.

### SAML hostname consistency

All of these must match:

| Config location | Value |
|---|---|
| Entra Enterprise App: Identifier (Entity ID) | `https://trading.rooez.com/[AppGroupName]/saml/sp/metadata` |
| Entra Enterprise App: Reply URL (ACS) | `https://trading.rooez.com/[AppGroupName]/+CSCOE+/saml/sp/acs?tgname=[AppGroupName]` |
| FTD ZTAA application URL | `https://trading.rooez.com` |
| FTD identity certificate CN/SAN | `trading.rooez.com` |
| Cloudflare A record (ZTAA) | `trading.rooez.com` > FTD public IP |
| Cloudflare A record (RAVPN) | `vpn.rooez.com` > FTD public IP |

Mismatch in any of these breaks SAML or TLS.

### TLS certificate for FTD

Options:

1. **Let's Encrypt (free):** Generate cert for `trading.rooez.com` using DNS-01 challenge via Cloudflare API. Import cert + key into cdFMC as PKI object.
2. **Self-signed:** Works for demo if you accept the browser warning. Entra does not care about the FTD cert (it validates the SAML assertion signature, not the TLS cert). But the browser will warn on first visit.
3. **Cloudflare Origin CA:** Free 15-year cert. Only valid behind Cloudflare proxy, which we are not using. Skip this option.

Recommendation: Let's Encrypt. Clean browser experience, no warnings, free.

### TLS certificate generation (Let's Encrypt + Cloudflare)

One SAN cert covers both RAVPN and ZTAA hostnames. Run from any Linux box with internet access (local machine or one of the Ubuntu VMs in Azure).

**Prerequisites:**

- Cloudflare API token with Zone:DNS:Edit permissions for rooez.com
- Python 3 and pip

**Steps:**

```bash
# Install certbot with Cloudflare DNS plugin
pip install certbot certbot-dns-cloudflare --break-system-packages

# Create Cloudflare credentials file
mkdir -p ~/.secrets/certbot
cat > ~/.secrets/certbot/cloudflare.ini << 'CREDS'
dns_cloudflare_api_token = <your-cloudflare-api-token>
CREDS
chmod 600 ~/.secrets/certbot/cloudflare.ini

# Generate SAN cert for both hostnames
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials ~/.secrets/certbot/cloudflare.ini \
  -d trading.rooez.com \
  -d vpn.rooez.com \
  --preferred-challenges dns-01
```

**Output files (default location: `/etc/letsencrypt/live/trading.rooez.com/`):**

| File | Use |
|---|---|
| `fullchain.pem` | Certificate chain (server cert + intermediate). Import into cdFMC as identity cert. |
| `privkey.pem` | Private key. Import into cdFMC paired with the cert. |

**Import into cdFMC:**

1. Objects > Object Management > PKI > Internal Certificates > Add.
2. Paste `fullchain.pem` contents into Certificate field.
3. Paste `privkey.pem` contents into Key field.
4. Name: `rooez-letsencrypt` (or similar).
5. Assign to FTD outside interface for RAVPN.
6. Assign to ZTAA application as the identity/proxy cert.

**Renewal:** Let's Encrypt certs expire after 90 days. Run `certbot renew` and re-import. For a one-week demo, expiry is not a concern.

### Application certificate (ZTAA backend)

Self-signed cert for the ZTAA backend app (10.100.3.20, `/ztaa` route). Only FTD connects to this backend. No browser sees it.

```bash
# Run on the trading app VM (10.100.3.20)
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout /etc/ssl/private/ztaa-app.key \
  -out /etc/ssl/certs/ztaa-app.crt \
  -days 30 \
  -subj "/CN=ztaa-app-internal"

# Configure nginx to use this cert
# (handled by the ZTAA app deploy script)
```

Export `ztaa-app.key` and `ztaa-app.crt` from the VM. Import into cdFMC as a PKI object (Internal Certificate). Assign to the ZTAA application object for known-key TLS decryption (Snort 3 inspection).

### Certificate summary

| Cert | Hostnames | Type | Source | Used by |
|---|---|---|---|---|
| rooez-letsencrypt | `trading.rooez.com`, `vpn.rooez.com` | Let's Encrypt (CA-signed) | DNS-01 via Cloudflare | FTD outside interface (RAVPN SSL), ZTAA identity/proxy cert |
| ztaa-app-internal | N/A (internal only) | Self-signed | Generated on trading app VM (10.100.3.20) | ZTAA application cert in cdFMC (known-key decryption) |

### DNS resolution for internal VMs

Azure-provided DNS (168.63.129.16) handles all public hostname resolution for ISE (login.microsoftonline.com, graph.microsoft.com) and FTD management (cdFMC cloud endpoint). No custom DNS server needed. No Cloudflare entries needed for ISE or FTD backend connectivity.

### Demo identity structure

| Element | Value |
|---|---|
| App URL | `https://trading.rooez.com` |
| Demo user | `trader1@rooez.com` |
| IdP | Microsoft Entra ID |
| MFA | Microsoft Authenticator (push) |

### Failure modes to avoid

- Domain not verified in Entra: cannot assign `@rooez.com` UPN
- Cloudflare proxy enabled (orange cloud): breaks TLS/SAML flow
- Cert CN/SAN mismatch with hostname: browser or FTD rejection
- Entity ID in Entra does not match FTD SP Entity ID: SAML assertion rejected

### Setup sequence

1. Add `rooez.com` to Entra and verify via TXT record in Cloudflare
2. Create `trader1@rooez.com`, register Microsoft Authenticator, enable MFA
3. Create A records in Cloudflare: `trading.rooez.com` and `vpn.rooez.com`, both pointing to FTD public IP (gray cloud)
4. Generate Let's Encrypt SAN cert for both hostnames via DNS-01/Cloudflare (see "TLS certificate generation" section)
5. Import cert + key into cdFMC. Assign to FTD outside interface.
6. Generate self-signed cert on ZTAA app VM. Export key. Import into cdFMC as application cert.
7. Proceed to SAML config (Entra Enterprise App + cdFMC SSO Server Object)

---

## cdFMC VPN dashboard demo

The cdFMC Remote Access VPN dashboard provides real-time visibility into VPN sessions. This is a passive demo element: connect one or more Secure Client sessions, then walk through the dashboard with the audience.

Key dashboard views to show:

| View | What it shows | Workshop relevance |
|---|---|---|
| Active sessions | Connected users, assigned IPs, tunnel protocol (SSL/DTLS/IKEv2), duration, bytes transferred | Replaces ASA `show vpn-sessiondb` CLI. Centralized view across all managed FTDs. |
| Connection profile summary | Sessions grouped by connection profile (tunnel group) | Maps to a typical multi-use-case model. Each use case gets its own connection profile. |
| Geographic distribution | Session origin by country/region (if geolocation data available) | Ties directly to geolocation VPN demo. |
| Throughput and trends | Historical session counts, bandwidth consumption | Capacity planning context for large-scale endpoint deployments. |
| Secure Client version | Client software versions across active sessions | Relevant to AnyConnect-to-Secure-Client migrations. |

The dashboard eliminates the need for CLI-based monitoring and provides the centralized multi-device visibility that CSM (now end-of-life) never offered for VPN sessions.

[from notebook source: FMC admin guide, FTD RAVPN admin guide]

---

## Geolocation VPN demo

Geolocation RAVPN allows FTD to steer VPN connections based on the client's geographic location. Policies can restrict, redirect, or apply different group policies based on where the connection originates.

### Demo approach

Configure two connection profiles on the FTDv:

1. **Default profile:** Standard RAVPN access to the VPN trading dashboard (10.100.3.20). No geographic restriction.
2. **Geo-restricted profile:** Apply a different group policy (or deny access) when the client connects from a specific country/region.

Show the policy configuration in cdFMC, connect from two locations (or simulate using a VPN endpoint in a different Azure region), and demonstrate how FTD applies different policies based on origin.

### Configuration elements

| Element | Detail |
|---|---|
| Geolocation objects | cdFMC Objects > Geolocation. Built-in country/continent database (updated through Threat Intelligence Director or manual feed). |
| Access control rules | Use geolocation objects as source conditions in ACP rules to permit/deny/redirect VPN traffic post-tunnel. |
| Connection profile assignment | Secure Client XML profile can use `<AutomaticVPNPolicy>` with geolocation awareness, or FTD can apply group policy overrides based on source geo. |
| Dashboard correlation | cdFMC VPN dashboard shows geographic distribution of active sessions, providing visual confirmation of the policy effect. |

This maps to workshop Section 6 (Geolocation VPN) and addresses global topologies (multi-region across NA, EMEA, APAC).

[from notebook source: FTD RAVPN admin guide, geolocation RAVPN doc]

---

## Multi-instance introduction (conceptual, not deployed)

Multi-instance is not deployed in this demo environment. It is introduced as a conceptual overview during the workshop to frame a future use case for multi-tenant VPN architectures.

### What multi-instance provides

FTD multi-instance on Firepower 4200 series appliances allows multiple independent FTD instances on a single chassis, each with its own configuration, policies, interfaces, and management. Each instance operates as an isolated firewall with dedicated CPU, memory, and interface allocation.

### Production relevance

Many large enterprises run three environments (PROD, ENG, UAT) on separate physical appliances today. Multi-instance on FP4200 could consolidate these onto fewer chassis with hardware-level isolation between instances. Each instance registers independently to FMC/cdFMC and receives its own policy set.

### Workshop talking points

| Point | Detail |
|---|---|
| Hardware isolation | Each instance gets dedicated resource allocation. No shared-state risk between PROD and non-PROD. |
| Independent management | Each instance registers separately to cdFMC. Different admin teams can manage different instances. |
| Migration path | FP4140 to FP4200. Multi-instance is native on 4200. Not available on 2100/3100 series. |
| Licensing | Each instance requires its own FTD license entitlement. |
| Limitations | Not supported on FTDv (Azure demo is single-instance only). Requires physical 4200 hardware. |

This is a discussion topic only. No configuration or deployment required for the demo.

[from notebook source: FMC Device Config Guide 10.0, FP4100 Getting Started Guide]

---

## Microsoft Entra ID (SAML IdP for ZTAA demo)

Entra ID replaces Keycloak as the SAML IdP. No on-prem VM required. Configured entirely in the Azure portal. Entra ID provides SAML 2.0 SSO and MFA through Microsoft Authenticator.

### Why Entra ID

ZTAA on FTD requires a SAML IdP. Entra ID is already available with any Azure subscription, requires no additional infrastructure, supports MFA natively through Microsoft Authenticator, and demonstrates a realistic enterprise IdP integration. The demo user does not require an M365 license.

### Configuration

See `outputs/ztaa-demo-notes.md` for the full step-by-step setup. Summary:

1. Create a demo user in Entra (e.g., `trader1@yourdomain.com`). No license required.
2. Register Microsoft Authenticator for the demo user (https://aka.ms/mfasetup).
3. Enable per-user MFA in Entra for the demo user.
4. Create a non-gallery Enterprise Application (`FTD-ZTAA-TradingApp`).
5. Configure SAML SSO: Entity ID = `https://trading.rooez.com/[AppGroupName]/saml/sp/metadata`, ACS URL = `https://trading.rooez.com/[AppGroupName]/+CSCOE+/saml/sp/acs?tgname=[AppGroupName]`.
6. Set NameID = `user.userprincipalname`. Optional attributes: `user.displayname`, `user.mail`.
7. Download Federation Metadata XML. Import into FTD via cdFMC.

### Demo flow

User hits Trading Dashboard URL > FTD intercepts > redirects to Entra > user logs in + approves push in Authenticator > FTD enforces policy > app loads.

---

## ROPC and MFA: two separate auth paths by design

The RAVPN and ZTAA demos use two intentionally different authentication architectures. MFA is not on the RAVPN path. This is a design choice, not a workaround.

| Path | Auth flow | MFA? | Reason |
|---|---|---|---|
| RAVPN | FTD > ISE (RADIUS) > Entra ID (ROPC) | No | ROPC is non-interactive. MFA requires interactive challenge. These are incompatible. Demo validates ISE + Entra integration with username/password auth. |
| ZTAA | FTD > Entra ID (SAML) + Authenticator | Yes | SAML is browser-based and interactive. MFA push via Authenticator works natively. Demo validates app-level zero trust with strong auth. |

### Why ROPC cannot support MFA

ISE REST ID uses OAuth ROPC to send credentials to Entra in a backend call. ROPC cannot present an interactive MFA challenge (push, number matching, FIDO2). When MFA is enforced for a user and ROPC is attempted, Entra blocks the authentication outright. It does not degrade or prompt. It fails.

Cross-validated sources:

- Microsoft ROPC documentation: ROPC cannot handle interactive MFA. [from notebook source: Azure/Microsoft docs notebook, b820b4c2]
- ISE REST ID config guide: REST Auth Service is non-interactive. [from notebook source: ISE & Duo notebook, 9a2f727a]
- ISE and Catalyst Center docs: ISE REST ID uses ROPC, no MFA pathway. [from notebook source: ISE and Catalyst Center notebook, e59c6d02]
- Microsoft enforcement timeline: CA MFA enforcement changes began March 27, 2026. [from web: Microsoft Entra security defaults documentation]

### Tenant-wide MFA protection

If the Entra tenant has tenant-wide MFA enforced (via security defaults or Conditional Access), create a Conditional Access policy that excludes the ISE ROPC app registration from MFA:

1. Entra > Protection > Conditional Access > New policy.
2. Assignments: All users (or demo users).
3. Target resources: Exclude the ISE ROPC app registration (by client ID).
4. Grant: Require MFA for all other apps.
5. Result: ROPC succeeds for the ISE app. MFA remains enforced for ZTAA and all other apps.

If tenant-wide MFA is not enforced, no Conditional Access policy is needed. ROPC works without MFA by default.

### Production path (MFA on RAVPN)

If MFA on the RAVPN path is required in production, ROPC is not viable. Alternatives:

| Alternative | How it works | Avoids ROPC? | MFA compatible? |
|---|---|---|---|
| EAP-TLS/TEAP + REST lookup | ISE authenticates via client certificate (no password). REST API call to Entra Graph for group/attribute retrieval. ISE 3.2+. | Yes | Yes (cert is the strong factor) |
| SAML for portal flows | Captive portal or clientless. Not applicable to Secure Client machine-tunnel. | Yes | Yes |
| Duo External MFA via Entra | Route MFA through Duo integrated with Entra. Adds complexity. | No (still ROPC for primary auth) | Partial (Duo handles MFA separately) |

EAP-TLS/TEAP aligns with existing PKI/MDM cert auth architectures and is the strongest production option.

---

## Windows Server AD DC — REMOVED

AD DC removed from demo scope (4/24/26). ISE authenticates against Entra ID via REST ID (ROPC) instead of on-prem Active Directory. ZTAA authenticates directly via Entra SAML. No on-prem domain controller needed. Demo users and groups are managed in Entra ID.

DNS for inside VMs uses Azure-provided DNS (168.63.129.16). No custom DNS server required.

---

## ISEv PSN node

ISE adds RADIUS authentication, posture assessment, and CoA to the demo. It is the most realistic representation of a production architecture (FTD + ISE + AD).

### Platform support

ISE supports native Azure IaaS deployment since ISE 3.2. ISE 3.5 is fully supported on Azure as a native VM. Available through Azure Marketplace (subscription license through Cisco partner private offer).

Supported cloud platforms for ISE: AWS (3.1+), Azure (3.2+), OCI (3.2+).

[from notebook source: ISE 3.5 administration guide (b_ise_admin_3_5.pdf), notebook 9a2f727a]

### Deployment

| Item | Value |
|---|---|
| VM size | Standard_D8s_v4 (8 vCPU, 32 GB RAM) |
| Persona | PSN only (Extra Small / ISELite / PSNLite). Does not run PAN or MnT. |
| Session capacity | Up to 1,000 or 12,000 sessions depending on deployment type. |
| Disk | 300 GB minimum. Write performance: 50 MB/s min, read: 300 MB/s min. |
| Version | ISE 3.5 |
| Subnet | identity (10.100.4.10) |
| License | ISE VM License (covers on-prem and cloud virtual appliances). |

Azure VM size mapping to SNS hardware equivalents:

| Azure VM Size | vCPU | RAM | SNS Equivalent | ISE Persona |
|---|---|---|---|---|
| Standard_D8s_v4 | 8 | 32 GB | Extra Small (ISELite/PSNLite) | PSN only |
| Standard_D16s_v4 | 16 | 64 GB | Small (SNS 3615) | All |
| Standard_F16s_v2 | 16 | 32 GB | Small (compute-optimized) | All |
| Standard_D32s_v4 | 32 | 128 GB | Medium (SNS 3715) | All |
| Standard_D64s_v4 | 64 | 256 GB | Large (SNS 3695/3795) | All |

For this demo, Standard_D8s_v4 (Extra Small, PSN-only) is sufficient.

[from notebook source: ISE 3.5 administration guide, ISE Performance and Scalability Guide]

### Post-deploy configuration

1. Install ISE 3.5 as PSN-only node.
2. Configure REST ID identity source (Entra ID):
   - Register an app in Entra (App registrations > New). Grant `User.Read.All` and `GroupMember.Read.All` API permissions (Application type, admin consent required).
   - In ISE: Administration > Identity Management > External Identity Sources > REST ID. Add Entra tenant ID, client ID, client secret.
   - ISE uses OAuth ROPC to validate username/password against Entra. Retrieves group membership for authorization policy.
   - ISE 3.2 patch 4+: 44 Entra user attributes available for authorization conditions.
3. Add FTDv as a Network Access Device (NAD) in ISE. Shared secret for RADIUS.
4. Configure Authentication policy: use REST ID (Entra) as identity source for RAVPN connection profiles.
5. Configure Authorization policy: map Entra groups to authorization profiles (DACL, VLAN, SGT as needed).
6. On cdFMC: add ISE as RADIUS server object. Assign to RAVPN connection profile.
7. Test: RAVPN auth flows through FTD > ISE (RADIUS) > Entra ID (ROPC). ISE returns authorization attributes.

### ISE outbound requirements (Entra integration)

ISE needs outbound HTTPS to Entra endpoints. NSG on the identity subnet must allow egress to:

- `login.microsoftonline.com` (TCP 443) — OAuth token endpoint
- `graph.microsoft.com` (TCP 443) — user/group attribute retrieval

### Ports (ISE PSN)

| Port | Protocol | Purpose |
|---|---|---|
| UDP 1812 | RADIUS | Authentication |
| UDP 1813 | RADIUS | Accounting |
| UDP 1700 | RADIUS | Change of Authorization (CoA) |
| TCP 49 | TACACS+ | Device administration (if needed) |
| TCP 443 | HTTPS | Admin GUI, API, outbound to Entra (login.microsoftonline.com, graph.microsoft.com) |
| TCP 8443 | HTTPS | Guest/sponsor/posture portals |
| TCP 8905 | TCP | Client provisioning agent |

[from notebook source: ISE 3.5 install guide, from web: Cisco ISE REST ID with Azure AD config guide]

---

## Azure platform limitations for FTDv

These are hard constraints. They apply to all FTDv deployments on Azure, not just this demo.

| Limitation | Detail |
|---|---|
| Transparent mode | Not supported. Azure does not allow promiscuous mode on NICs. Routed mode only. |
| High Availability (Active/Standby) | Not supported in Azure public cloud. Requires L2 connectivity. Use clustering (7.3+) or Azure load balancers instead. Not relevant for this single-FTDv demo. |
| Jumbo frames | Not supported on Azure. |
| VM generation | Gen 1 only. Gen 2 not supported. |
| IPv6 | Supported from FTD 7.3+ but requires custom ARM templates or VHD deployment. Marketplace wizard is IPv4 only. |
| Console password recovery | Not possible. No real-time serial console during boot. |
| Azure "reset password" | Not supported for FTDv. |
| Max resources (7.x) | 16 vCPU, 32 GB RAM. |
| Max resources (10.x) | 64 vCPU, 128 GB RAM (FTDvU tier). |
| Dv2 VM family | Supported on 7.7 and below only. Not supported on 10.x. Use Dsv3 or Fsv2 families. |

[from notebook source: FTDv Getting Started Guide 7.2, FMC Device Config Guide 10.0]

---

## Deployment method

### Terraform (primary)

All infrastructure deploys through Terraform using the `azurerm` provider. This aligns with the NaC pave/repave story (workshop Section 9) and produces a repeatable, version-controlled environment.

Terraform resources:

- `azurerm_resource_group`
- `azurerm_virtual_network` + 5 subnets (management, diagnostic, outside, inside, identity)
- `azurerm_network_security_group` x5
- `azurerm_public_ip` x2 (management, outside)
- `azurerm_network_interface` x4 (FTDv)
- `azurerm_marketplace_agreement` (accept Cisco EULA for FTDv, ISEv)
- `azurerm_linux_virtual_machine` (FTDv with custom_data Day-0 JSON)
- `azurerm_linux_virtual_machine` (Trading app, Ubuntu 22.04)
- `azurerm_linux_virtual_machine` (ISEv)

Post-deploy scripting:

- **Ubuntu VM (Trading app):** Bash script. Install packages, configure nginx with two routes (`/vpn` dark theme, `/ztaa` light theme), deploy static build. Executed through `azurerm_virtual_machine_extension` (CustomScript) or `custom_data` cloud-init.
- **ISEv:** Post-deploy configuration is manual (ISE GUI). REST ID identity source pointing to Entra, NAD config, auth/authz policies.
- **FTDv:** Day-0 bootstrap handles initial config. cdFMC registration is manual (SSH + paste `configure manager add` command from SCC). FTD is pre-registered before the live demo.
- **Entra ID:** Configured in Azure portal. Demo user creation, MFA enrollment, Enterprise App for ZTAA SAML, App Registration for ISE REST ID. No Terraform resource (portal-only).

Post-infra: Cisco FMC Terraform provider or NaC YAML + Terraform can push RAVPN/ZTAA policy config to cdFMC. Compatibility with cdFMC needs verification.

---

## Open items

| Item | Action | Status |
|---|---|---|
| cdFMC access | Verify Mario has an active Security Cloud Control tenant with cdFMC entitlement | Not started |
| Smart License | Confirm RAVPN (AnyConnect) entitlement in Smart Account for BYOL, or use PAYG | Not started |
| Secure Client .pkg | Download latest 5.x web-deploy packages (Windows, macOS) from cisco.com | Not started |
| FTDv version | Running 10.x per Mario's decision. Verify 10.0.x Marketplace image availability. Requires Dsv3 or Fsv2 VM family. | Decision made. Marketplace availability TBD. |
| Gen 2 VM support on 10.x | 7.2 and earlier: Gen 1 only. 10.0 docs do not explicitly confirm Gen 2. Verify at deploy time. | Unverified. |
| Entra ID SAML config (ZTAA) | Create Enterprise App in Entra, configure SAML SSO, enable MFA, download metadata XML. See ztaa-demo-notes.md. | Not started |
| Entra ID App Registration (ISE REST ID) | Register app for ISE ROPC. Grant User.Read.All and GroupMember.Read.All (Application type). Admin consent. Record tenant ID, client ID, client secret. | Not started |
| Entra ID Conditional Access | Only needed if tenant-wide MFA is enforced. Create CA policy excluding ISE ROPC app registration from MFA. See "ROPC and MFA" section. | Not started. Check tenant MFA state first. |
| Entra ID demo users | Create demo user(s) in Entra, assign to security groups, register Microsoft Authenticator for MFA. | Not started |
| ISEv deployment | ISE 3.5 native Azure IaaS (since 3.2). Standard_D8s_v4 for PSN-only. Azure Marketplace (Cisco partner private offer) or manual image upload. | Not started. |
| ISE REST ID config | Configure REST ID identity source in ISE pointing to Entra. Test ROPC auth. Configure auth/authz policies for RAVPN. | Not started. |
| ISE VM License | Requires ISE VM License entitlement in Cisco Smart Account. Covers on-prem and cloud. | Not started. |
| TLS certificates | One Let's Encrypt SAN cert for `trading.rooez.com` + `vpn.rooez.com` (DNS-01 via Cloudflare). One self-signed cert on trading app VM (10.100.3.20) for known-key decryption. See "TLS certificate generation" section. | Not started. Requires Cloudflare API token. |
| Trading app VM | React/Vite trading dashboard on Ubuntu B1s (10.100.3.20). Single app, two themes by route (`/vpn` dark, `/ztaa` light). Nginx serves static build + self-signed cert for backend TLS. | Not started |
| Azure subscription | Confirm subscription, resource limits, region selection | Not started |
| Terraform config | Write full Terraform config for all Azure resources (VNet, NSGs, VMs, PIPs). | Not started. |
| Bash script (Trading app) | Write bash script for trading app VM (nginx, React build deploy, two-route theme config). Deploy through CustomScript extension or cloud-init. | Not started. |
| Cisco FMC Terraform provider + cdFMC | Verify the Terraform provider works against cdFMC (not just on-prem FMC) | Not started. [general knowledge, not source-verified] |
| NaC + cdFMC compatibility | Confirm Network as Code YAML models work with cdFMC, not just on-prem FMC | Not started. [general knowledge, not source-verified] |
| Geolocation VPN config | Configure geolocation objects and geo-based access control rules in cdFMC. Validate with Secure Client from different regions. | Not started. |
| NSG hardening | Scope management NSG to Mario's IP + cdFMC cloud ranges (Cisco publishes these) | Not started |
| Demo script | Write step-by-step demo script for workshop walkthrough | Not started. Depends on environment being live. |

---

## Cost estimate (demo duration: ~1 week)

| Resource | SKU | Hourly | Daily (8h) | Weekly |
|---|---|---|---|---|
| FTDv | Standard_D8s_v3 | ~$0.45 | ~$3.60 | ~$25.20 |
| Trading App VM | Standard_B1s | ~$0.01 | ~$0.08 | ~$0.56 |
| ISEv | Standard_D8s_v4 | ~$0.46 | ~$3.68 | ~$25.76 |
| Public IPs x2 | Standard | ~$0.005 each | ~$0.24 | ~$1.68 |
| VNet/NSG | — | Free | Free | Free |
| Entra ID | — | Free (included with Azure subscription) | Free | Free |
| **Total** | | | | **~$53/week** |

Arithmetic: $25.20 + $0.56 + $25.76 + $1.68 = $53.20, rounded to ~$53.

Deallocate VMs when not in use. Costs drop to storage-only (~$1/week for managed disks).

[general knowledge, not source-verified. Azure pricing changes. Verify at azure.microsoft.com/pricing.]

---

## Timeline

| Phase | Task | Duration | Dependency |
|---|---|---|---|
| 1 | Verify cdFMC access, Smart License, Azure subscription | 1 day | None |
| 2 | Configure Entra ID: demo user(s), MFA enrollment, Enterprise App (ZTAA SAML), App Registration (ISE REST ID). If tenant-wide MFA is on, add CA exclusion for ISE app. | 1-2 hours | None (Azure portal only) |
| 3 | Write Terraform config for all Azure resources | 4-6 hours | Phase 1 |
| 4 | `terraform apply`: deploy VNet, subnets, NSGs, PIPs, all VMs (FTDv, trading app, ISEv) | 30 min | Phase 3 |
| 5 | Create Cloudflare A records (`trading.rooez.com`, `vpn.rooez.com`). Generate Let's Encrypt SAN cert via DNS-01. Generate self-signed cert on ZTAA app VM. | 30 min | Phase 4 (need FTD public IP for A records) |
| 6 | Trading app VM: build React/Vite dashboard (two theme routes), deploy static build to nginx | 2-3 hours | Phase 4 |
| 7 | Register FTDv to cdFMC (SSH + `configure manager add` from SCC) | 30 min | Phase 4 |
| 8 | ISEv post-deploy: configure REST ID identity source (Entra), add FTDv as NAD, auth/authz policies | 3-4 hours | Phases 2, 4 |
| 9 | Import certs into cdFMC. Configure and test RAVPN (connection profile with ISE RADIUS, group policy, address pool, NAT, certs) | 2-3 hours | Phases 5, 6, 7, 8 |
| 10 | Configure and test geolocation VPN (geo objects, geo-based ACP rules) | 1-2 hours | Phase 9 |
| 11 | Configure and test ZTAA with Entra ID SAML (import app cert, assign identity cert, SSO server object, app object, ZTA policy) | 2-3 hours | Phases 2, 5, 9 |
| 12 | Review cdFMC VPN dashboard with active sessions | 30 min | Phase 9 |
| 13 | Write demo script for workshop walkthrough | 2 hours | Phases 9-11 complete |

Total: ~4-5 days of hands-on work (no AD DC build/config time).
Spread across 1-2 weeks to allow for troubleshooting and cdFMC provisioning lead time.

Pre-demo state: Phases 1-8 complete. FTDv registered in cdFMC. ISE configured with Entra REST ID. Certs imported. All ancillary infrastructure running. Live demo begins at Phase 9.

---

## Demo flow

The live demo assumes all infrastructure is pre-built. The audience sees FTD configuration in cdFMC, policy deployment, and validation. The flow follows five blocks.

### Block 1: RAVPN configuration with ISE RADIUS + Entra ID (live in cdFMC)

1. Show FTDv registered in cdFMC inventory. Confirm device health and version (10.x).
2. Show ISE as RADIUS server object in cdFMC. Show ISE admin console with REST ID identity source pointing to Entra and Entra security groups in authorization policy.
3. Walk through RAVPN configuration: connection profile (with ISE RADIUS auth), group policy, address pool (10.100.200.0/24), identity certificate, Secure Client package upload.
4. Configure split-tunnel ACL to allow access to inside subnet (10.100.3.0/24).
5. Configure NAT exemption for VPN pool.
6. Deploy policy to FTDv from cdFMC.
7. On macOS, open Secure Client. Type `vpn.rooez.com` in the connection bar (no pre-configured profile, typed live). Hit Connect. Enter `trader1@rooez.com` and password. Auth flow: FTD > ISE (RADIUS) > Entra (ROPC). Show tunnel establishment, IP assignment.
8. Open the trading dashboard (10.100.3.20/vpn) in a browser. Dark theme loads. Confirm access. This app is unreachable without the tunnel.
9. Disconnect VPN. Show that the trading dashboard is no longer reachable.

### Block 2: cdFMC VPN dashboard

1. With one or more Secure Client sessions active, navigate to the cdFMC RAVPN dashboard.
2. Walk through active sessions: user, IP, tunnel protocol, duration, bytes.
3. Show connection profile grouping (maps to typical multi-use-case models).
4. Show geographic distribution view (sets up Block 3).
5. Show throughput trends and Secure Client version inventory.

### Block 3: Geolocation VPN

1. Show geolocation objects in cdFMC (country/continent database).
2. Create or show a pre-built access control rule that applies a different group policy based on client origin.
3. Connect from two locations (or simulate with a second Azure region endpoint) to demonstrate geo-based policy differentiation.
4. Return to the VPN dashboard geographic view. Confirm sessions appear with correct location data.
5. Discuss implications for global topologies (NA, EMEA, APAC routing decisions).

### Block 4: ZTAA with Entra ID SAML + MFA (live in cdFMC)

1. In cdFMC, show the SSO Server Object (Entra ID metadata, signing cert).
2. Create or show the ZTAA application object pointing to the trading dashboard (10.100.3.20, `/ztaa` route).
3. Create or show the Zero Trust Application Policy with SAML-authenticated user-to-app mapping.
4. Deploy policy.
5. Open a browser (no VPN client). Navigate to the ZTAA application URL. FTD intercepts, redirects to Entra ID login.
6. Authenticate with demo user credentials. Approve MFA push in Microsoft Authenticator. Entra issues SAML assertion. FTD validates, proxies to the app.
7. Show the trading dashboard in light theme (`/ztaa` route). Visual contrast with dark theme from VPN demo. Confirm access.
8. Contrast with Block 1: VPN requires a client and grants network-level access. ZTAA requires only a browser and grants app-level access. MFA enforced upstream in Entra. No RADIUS anywhere in the ZTAA flow.

### Block 5: Multi-instance overview (conceptual, no live demo)

1. No configuration shown. This is a whiteboard/slide discussion.
2. Explain multi-instance on FP4200: multiple independent FTD instances per chassis.
3. Map to a typical three-environment model (PROD/ENG/UAT). Each environment becomes its own instance on shared hardware.
4. Highlight: hardware-level isolation, independent cdFMC registration, separate policy sets, dedicated resource allocation.
5. Note: multi-instance is not available on FTDv. Requires physical 4200 hardware. This is a future phase discussion, not a PoV deliverable.
