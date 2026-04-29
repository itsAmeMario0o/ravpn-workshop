---
layout: default
title: The live management view
permalink: /demos/cdfmc-dashboard/
eyebrow: Demo 4
summary: While the audience watches the user connect, you switch tabs and show them what the firewall is reporting in real time.
---

## The story

The audience just watched Maya connect from the previous demo. They saw the icon turn green and the dashboard load. Now you switch tabs.

On the cloud manager (cdFMC), the live dashboard is already open. Maya's session is on it. Her username, her source IP, her country on a map, the version of the Cisco app she's running, when she connected, how much traffic has gone through the tunnel. All of it. Without a single extra click.

The point of this demo is not the dashboard itself. The point is that the dashboard is just there. Nothing to install. Nothing to back up. No on-premises management server.

## What the audience sees

- A live map with a pin on Maya's country.
- A row in a session list: username, source IP, app version, connect time, traffic counters.
- A second click into the rule that allowed her in. The same screen the admin used to configure the rule.

## Why this matters

In the older way of doing this, the management server was a virtual or physical box you had to install, patch, license, back up, and reach. If you wanted the live VPN dashboard, you ran it on that server. If the server went down, so did your visibility.

cdFMC ("cloud-delivered Firepower Management Center") is the same management plane delivered as a service by Cisco. Nothing on the customer side to install. Same policy editor, same dashboard, same firewall behind it. For a workshop with a one-day budget, the absence of an on-premises management server is the headline.

## What is configured

Nothing extra. The dashboard appears the moment the firewall is registered to cdFMC, and the moment a VPN session is active. The cdFMC tenant itself is provisioned through a Cisco service called Security Cloud Control before the build starts.

## What to point out

- **No on-premises manager.** Stand on this. There is nothing to patch and nothing to back up.
- **Same policy model.** Click into a connection profile or a rule from the dashboard. The editor that opens is the same one the admin used during setup.
- **Live, not polled.** Sessions appear within seconds of connect.

## Where to find the setup

- [`setup/scc-onboarding.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/scc-onboarding.md) covers provisioning the cdFMC tenant.
- [`setup/cdFMC-registration.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/cdFMC-registration.md) covers the firewall's first registration.
