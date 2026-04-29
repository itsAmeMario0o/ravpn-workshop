---
layout: default
title: Browser-only access
permalink: /demos/ztaa/
eyebrow: Demo 3
summary: No app installed, no tunnel, no IT setup on the laptop. Just a browser, a Microsoft sign-in, a phone push, and the dashboard loads.
---

## The story

Marco is a contractor. The client has hired him for two weeks and given him an account in their Microsoft directory. They have not installed anything on his personal laptop and they would rather not.

He opens his browser and goes to `https://trading.rooez.com/ztaa`. The browser bounces over to Microsoft. He types his password. His phone buzzes with a push from the Microsoft Authenticator app. He taps approve. Microsoft sends him back to the dashboard. He works for an hour, closes the browser, and his access is gone.

No VPN app. No tunnel. No software install. The whole sign-in is a normal "Sign in with your work account" flow.

## What the audience watches

1. Open a browser. Visit `https://trading.rooez.com/ztaa`.
2. The page redirects to Microsoft.
3. Sign in as `trader1@rooez.com`.
4. The phone shows a Microsoft Authenticator push. Approve it.
5. The browser returns to the trading dashboard. The page is the light theme.

The whole interaction lives in one browser tab. The audience can see the address bar change at each step.

## What is happening underneath

```text
Browser  --HTTPS-->  Firewall
                       |
                       | "No sign-in cookie yet, go sign in over there"
                       v
                     Microsoft Entra ID
                       |
                       | Asks for password
                       | Sends a push to the user's phone
                       v
                     User approves on the Microsoft Authenticator app
                       |
                       v
                     Microsoft sends a signed message back to the browser
                       |
                       v
Browser  -->  Firewall  reads the signed message, decides yes
                       |
                       v
                     Trading dashboard
```

The firewall acts as the front desk for one specific application. It does not let anyone in without a signed note from Microsoft saying who they are. The protocol is called SAML. It is the same one behind almost every "Sign in with Microsoft" or "Sign in with Google" button you have ever clicked.

## How this differs from the VPN demo

| | VPN sign-in | Browser-only |
| --- | --- | --- |
| What the user installs | The Cisco app | Nothing |
| The sign-in protocol | RADIUS to a middleman, then ROPC to Microsoft | SAML, browser to Microsoft directly |
| Multi-factor | Not possible on this path | Yes, phone push |
| What the user can reach after sign-in | Anything on the office network | Only this one app |
| What is granted | An IP address inside the network and a tunnel | A short-lived browser session |
| Best for | Power users, internal apps that need full network access | Contractors, BYOD laptops, single-app access |

The browser path gives the user a much narrower door. They can reach the dashboard. They cannot reach anything else on the network. There is no tunnel to leak across. If the laptop is compromised tomorrow, the worst that happens is the attacker reaches the dashboard during the session window.

## What is configured, and where

| Layer | What | Where |
| --- | --- | --- |
| Microsoft Entra | An Enterprise App configured for SAML, multi-factor enforced for the demo user, the certificate Microsoft signs with | Microsoft Entra portal |
| Firewall | A SAML server object pointing at Microsoft, an Application Group for the trading app, the certificates that prove the firewall's identity, and the certificate that protects the connection from the firewall back to the dashboard server | Cloud manager (cdFMC) |
| Trading dashboard | An Nginx web server serving the React app at `/ztaa`, listening with a self-signed certificate | Ubuntu virtual machine |
| DNS | A record at Cloudflare for `trading.rooez.com` pointing at the firewall's public address. Gray cloud. | Cloudflare |
| Certificates | Three: a public Let's Encrypt one for the firewall's identity, the Microsoft signing certificate, and a self-signed one for the dashboard | Three different upload spots inside the cloud manager |

## What goes wrong, and how to spot it

<div class="callout callout-warning">
<strong>The "AppGroupName" placeholder is literal.</strong>
When Microsoft and the cloud manager are wired together, both sides reference an Entity ID and a callback URL. The text in those fields contains the literal string `[AppGroupName]`. Replace it on both sides with the real name of the app group, or sign-in fails with an error that does not name the placeholder. This trips up everyone the first time.
</div>

<div class="callout callout-warning">
<strong>Three certificates, three places.</strong>
The firewall identity certificate (from Let's Encrypt), the SAML signing certificate (from Microsoft), and the application certificate (self-signed for the dashboard server) each go in a different spot in the cloud manager. The setup notes in `tls-certs.md` have the exact paths.
</div>

<div class="callout callout-danger">
<strong>Cloudflare proxy is on.</strong>
If the gray cloud is orange, the redirect from Microsoft back to the firewall lands in Cloudflare instead. The signed message gets mangled and the firewall rejects it. Gray cloud only.
</div>

## Where to find the exact steps

- [`setup/ztaa-config.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/ztaa-config.md) walks through the cloud manager and Microsoft setup.
- [`setup/ztaa-extensions.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/ztaa-extensions.md) shows how the same pattern protects other internal web apps, like the ISE admin GUI.
- [`setup/tls-certs.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/tls-certs.md) is the certificate cheat sheet.
