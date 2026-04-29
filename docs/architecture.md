---
layout: default
title: How it fits together
permalink: /architecture/
eyebrow: Plan
summary: One private network in Microsoft Azure, a firewall in front of it, a directory for sign-ins, an application server behind it, and a side door for admins. Five pieces. That is the whole build.
---

## A simple picture first

Think of an office building.

- The **firewall** is the front door. Every visitor passes through it.
- The **directory** is the receptionist who looks up names and checks IDs.
- The **trading dashboard** is the office on the inside that visitors come to see.
- The **secure side door** is how the building's staff get in to fix things, without walking past the public lobby.
- The **management dashboard** is the building manager's screen, except it lives in the cloud and watches every door at once.

Everything else on this page is detail about which piece is which, and how they reach each other.

## The five pieces

| Piece | What it actually is | What it does in the demo |
| --- | --- | --- |
| Firewall | A virtual Cisco firewall (called FTDv, short for Firepower Threat Defense Virtual). It is the same firewall capability as Cisco's hardware appliance, running as a virtual machine in Azure. | The front door. Terminates the VPN tunnel. Brokers the browser-only sign-in. |
| Directory | Microsoft Entra ID (the new name for Azure AD, Microsoft's identity service). | Holds the user accounts. Validates passwords. Sends the phone push for multi-factor. |
| Identity middleman | Cisco ISE (Identity Services Engine). A virtual machine running Cisco's policy server. | Sits between the firewall and Microsoft. Speaks RADIUS to the firewall (the protocol VPN servers use to ask "is this password valid?") and modern web protocols to Microsoft. |
| Trading dashboard | A small React web app on a tiny Ubuntu virtual machine. | The thing the user is trying to reach. Has two looks: a dark page at `/vpn` for the VPN demo, a light page at `/ztaa` for the browser demo. |
| Secure side door | Azure Bastion, a Microsoft service. | Lets admins reach the firewall and the identity server through the browser, without exposing them to the public internet. |
| Cloud manager | cdFMC (cloud-delivered Firepower Management Center). Cisco's management plane, run as a service. | The single screen that configures the firewall and shows live VPN sessions on a map. |

If you only remember three names, make them **firewall**, **directory**, and **cloud manager**. The rest are supporting roles.

## Where it all lives

Everything runs in one private network inside Azure called a Virtual Network, or VNet. The VNet is divided into smaller sections (subnets), one for each role:

| Subnet | Address range | Who lives here |
| --- | --- | --- |
| Management | `10.100.0.0/24` | The firewall's admin connection. No public address. Reached only through the secure side door. |
| Diagnostic | `10.100.1.0/24` | A second firewall connection, unused in this demo, but the firewall image needs four connections to start. |
| Outside | `10.100.2.0/24` | The firewall's public-facing connection. This is where VPN tunnels and browser traffic land. |
| Inside | `10.100.3.0/24` | The firewall's internal connection and the trading dashboard server. |
| Identity | `10.100.4.0/24` | The Cisco ISE server. |
| AzureBastionSubnet | `10.100.5.0/26` | The secure side door for admins. The name is required by Azure. |

Public traffic only ever lands on one address: the firewall's outside connection. Everything else is private.

## The diagram

```text
Internet
   |
   v
+----------------------------------------------------------------------+
|  Azure Virtual Network: 10.100.0.0/16                                |
|                                                                       |
|  Firewall (FTDv)                                                      |
|    Connection 0 (admin)        10.100.0.10  private                  |
|    Connection 1 (diagnostic)   10.100.1.10                           |
|    Connection 2 (outside)      10.100.2.10  public IP                |
|    Connection 3 (inside)       10.100.3.10                           |
|                                                                       |
|  Trading dashboard server (Ubuntu)                                   |
|    10.100.3.20                                                        |
|    Two pages: /vpn (dark theme), /ztaa (light theme)                 |
|                                                                       |
|  Identity middleman (Cisco ISE)                                      |
|    10.100.4.10                                                        |
|                                                                       |
|  Secure side door (Azure Bastion)                                    |
|    Browser-based access for admins. No public IPs on the firewall    |
|    admin connection or the identity server.                          |
+----------------------------------------------------------------------+
         |
         v
   Cloud manager (cdFMC, Cisco's management service)
```

## How a sign-in actually flows

### The VPN path

```text
User's laptop  --VPN tunnel-->  Firewall  --check this password-->  Identity middleman  --check this password-->  Microsoft
```

The user types a password into the Cisco VPN app. The firewall does not know if the password is right, so it asks the identity middleman over a protocol called RADIUS. The middleman cannot ask Microsoft directly in RADIUS, so it translates the question into a modern web protocol (called ROPC, or Resource Owner Password Credentials) and asks Microsoft. Microsoft answers yes or no. The answer travels back through the same chain. If yes, the firewall lets the tunnel come up.

The trade-off: ROPC sends the password straight through. There is no opportunity to send a phone push along the way. So the VPN path is password-only.

### The browser-only path

```text
User's browser  --HTTPS-->  Firewall  --redirect-->  Microsoft  --phone push-->  User
                                                       |
                                                       v
                                                   Sign-in confirmed
                                                       |
                                                       v
User's browser  <--redirect back--                  Firewall  --forward-->  Trading dashboard
```

The user types the address. The firewall sees there is no sign-in cookie yet, so it bounces the browser to Microsoft. Microsoft handles the whole sign-in: password, phone push, the lot. When Microsoft is happy, it sends the browser back to the firewall with a signed message. The firewall reads the message, decides yes, and forwards the request to the trading dashboard.

This is called SAML (Security Assertion Markup Language). It is the same protocol behind almost every "Sign in with your work account" button on the web.

## Public addresses and names

Two web addresses point at the same firewall. Both go through Cloudflare for DNS:

- `vpn.rooez.com` is what the VPN app connects to.
- `trading.rooez.com` is what the browser hits for the zero-trust path.

Both names share one TLS certificate (the small file that proves the firewall really is who it claims to be). The certificate is issued by Let's Encrypt, a free public certificate authority.

<div class="callout callout-warning">
<strong>Cloudflare proxy must be off.</strong>
Cloudflare can either just answer DNS questions (a gray cloud icon) or also act as a proxy in front of your traffic (an orange cloud). The orange cloud breaks both demos. Keep the gray cloud.
</div>

## How admins get in

The firewall's admin connection has no public address. Neither does the identity server. Both can only be reached from inside Azure. To get in, an admin opens Azure Bastion in the browser, picks the machine, and Bastion brokers a private session.

The cloud manager (cdFMC) talks to the firewall over a private outbound connection that the firewall opens itself, sourced from the outside connection. This means there is no inbound admin port open on the public internet. Anywhere.

## Constraints worth knowing

- **No active/standby pair.** This virtual firewall on Azure does not support paired failover. The demo runs on one firewall.
- **One way for the firewall to start.** The firewall is built from a Cisco image in the Azure Marketplace, which has its own quirks. Notes are in [`LESSONS-LEARNED.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/LESSONS-LEARNED.md).
- **Two sign-in protocols, two outcomes.** The VPN path cannot do multi-factor. The browser path can and does. That is by design.

## Naming and tags

Every resource follows the same name pattern: `<type>-<role>`, lowercase, hyphenated. Examples: `vnet-demo`, `vm-ftdv`, `pip-ftdv-outside`, `bastion-demo`. Three tags go on every resource: `project=ravpn-demo`, `environment=demo`, `owner=mario`.

## Where to find this in the repo

- The cloud build (Terraform): [`infra/`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/tree/{{ site.repo.branch }}/infra)
- The trading dashboard app: [`app/`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/tree/{{ site.repo.branch }}/app)
- The longer architecture reference: [`azure-demo-plan.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/azure-demo-plan.md)
