---
layout: default
title: VPN sign-in
permalink: /demos/ravpn/
eyebrow: Demo 1
summary: A trader on a hotel wifi needs to reach the dashboard. She opens the VPN app, signs in, and the dashboard loads. Close the app, the dashboard is gone again.
---

## The story

Maya is a trader. She is on hotel wifi at a conference. The dashboard she needs is on the company's private network in Azure, which the hotel wifi cannot see.

She opens the Cisco Secure Client app on her laptop. She types in `vpn.rooez.com`. She enters her work email and password. The app builds an encrypted tunnel to the company firewall. The browser loads the dashboard. She places her trades, closes the app, and the connection drops. The dashboard is back to being invisible from the hotel wifi.

That is the demo. About forty seconds, start to finish.

## What the audience watches

1. Open Cisco Secure Client on the laptop.
2. Connect to `vpn.rooez.com`.
3. Type `trader1@rooez.com` and the demo password.
4. The tunnel comes up. A small icon turns green.
5. Open a browser. Visit `https://vpn.rooez.com/vpn`. The dark trading dashboard loads.
6. Click disconnect. The same browser tab no longer reaches the dashboard.

## What is happening underneath

```text
Maya's laptop  --encrypted tunnel-->  Firewall (FTDv)
                                       |
                                       | "Is this password right?"
                                       v
                                    Identity middleman (ISE)
                                       |
                                       | Translates the question
                                       v
                                     Microsoft Entra ID
                                       |
                                       | "Yes, that password is valid"
                                       v
                                       (answer travels back the same way)
```

Three short hops:

1. **Laptop to firewall.** The Cisco app builds an encrypted tunnel using TLS, the same encryption your browser uses for HTTPS. The firewall is the only public-facing piece of this whole demo.
2. **Firewall to identity middleman.** The firewall does not know who the user is. It asks the identity middleman over RADIUS, the protocol VPN servers and wifi networks use to ask "is this password valid?".
3. **Identity middleman to Microsoft.** RADIUS itself cannot ask a modern cloud directory like Microsoft. So the middleman acts as a translator. It takes the username and password and asks Microsoft over a web protocol. Microsoft answers yes or no.

The "yes" travels back the same way. The firewall reads it, brings the tunnel up, and assigns the laptop a private IP address inside the company network. The browser can now see the dashboard.

## Why no phone push on this path

This demo is password-only on purpose. The protocol the middleman uses to talk to Microsoft (called ROPC) sends the password directly. There is no place in that conversation for Microsoft to send a phone push and wait for the user to tap it. So this path uses passwords alone.

The next demo, the browser-only path, uses a different protocol that does support multi-factor. The point of having both demos is showing the choice.

## What is configured, and where

| Layer | What | Where |
| --- | --- | --- |
| Firewall | The VPN connection profile, the pool of IP addresses for connected users, the access rules, the certificate that proves the firewall's identity | Cloud manager (cdFMC) under Devices > Remote Access VPN |
| Identity middleman | A REST identity store that points at Microsoft, the firewall registered as an authorized client, a policy that says "if the password is good, allow the connection" | Cisco ISE web GUI |
| Microsoft Entra | An app registration that allows password sign-in, the demo user `trader1@rooez.com`, no multi-factor on this user for this app | Microsoft Entra portal |
| DNS | An A record at Cloudflare for `vpn.rooez.com` pointing at the firewall's public address. Gray cloud, not orange. | Cloudflare |
| Certificate | A free Let's Encrypt certificate that covers `vpn.rooez.com` and `trading.rooez.com` | Cloud manager, under Devices > Certificates |

## Where to find the exact steps

- [`setup/ravpn-config.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/ravpn-config.md) walks through the cloud manager configuration.
- [`setup/ise-config.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/ise-config.md) covers the identity middleman.
- [`setup/entra-config.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/entra-config.md) covers the Microsoft side.

## What goes wrong, and how to spot it

<div class="callout callout-warning">
<strong>Cloudflare proxy is on.</strong>
If the cloud icon next to the DNS record is orange, the tunnel will not form. Click it back to gray (DNS only). The reason is that Cloudflare's proxy expects HTTP traffic, and the VPN tunnel is not HTTP.
</div>

<div class="callout callout-warning">
<strong>The middleman does not know the firewall.</strong>
The identity middleman accepts password questions only from firewalls it has been told about. If the firewall asks from an IP address the middleman does not recognize, the question is silently dropped. The middleman's live log shows nothing. The fix is to confirm the firewall's inside IP matches what is configured on the middleman's side.
</div>

<div class="callout callout-danger">
<strong>The certificate does not cover the name.</strong>
The certificate bound to the VPN connection must include the name the user typed. If the certificate is for the wrong name, the Cisco app rejects the connection with a generic certificate error. The Let's Encrypt certificate in this build covers both `vpn.rooez.com` and `trading.rooez.com` by design.
</div>
