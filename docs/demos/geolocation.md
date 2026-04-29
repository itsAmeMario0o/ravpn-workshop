---
layout: default
title: Different rules by location
permalink: /demos/geolocation/
eyebrow: Demo 2
summary: One firewall, two clients, two countries, two outcomes. The audience watches the same product behave differently based on where the user is connecting from.
---

## The story

Picture the same trader from the VPN demo, but now there are two of her. One is in Houston on a normal home internet connection. The other is, hypothetically, in a country the company does not do business with.

The firewall greets both with the same VPN address. It takes them down different paths the moment it sees where they are coming from. The Houston client lands on the dashboard. The other client gets a banner explaining the policy and goes no further.

## What the audience watches

1. Connect from a laptop on a normal home network. The trusted profile applies. The dashboard loads.
2. Switch to a VPN exit node in a different country, or use a second laptop on a different network.
3. Connect again. The firewall classifies the source country, applies the location-based rule, and the dashboard either fails to load or loads with a warning depending on how the rule was written.
4. Open the live management dashboard in the cloud manager. Both sessions are on the map, in different countries, with the rule that fired listed for each.

## How the firewall knows where the user is

Public IP addresses come from regional registries. The firewall ships with a database that maps every public IP block to a country. When a user connects, the firewall looks up the source IP, finds the country, and matches it against rules in the access policy. Two rules covering two countries, ordered correctly, are all the demo needs.

There is no extra licence and no third-party service to wire in. The data is built into the firewall.

## Why this matters in real life

Most companies have at least one rule that depends on geography. Examples:

- "Block sign-ins from countries we don't operate in."
- "Allow contractors only from a small list of partner countries."
- "Send users from the EU through a specific egress to satisfy data-residency rules."

Doing this with route changes or a second VPN endpoint per country is painful. Doing it with one rule on one firewall, managed from the cloud, is the point.

## What goes wrong, and how to spot it

<div class="callout callout-warning">
<strong>The geo lookup uses the public IP, not the laptop.</strong>
If the test laptop is going through a corporate VPN to the public internet, the firewall sees the corporate VPN's exit IP, not the laptop's. That can put the user in a different country from where they actually are. Be deliberate about which exit you are testing from.
</div>

<div class="callout callout-warning">
<strong>Rule order matters.</strong>
The firewall reads access rules from top to bottom and stops at the first match. A broad allow rule above the geo rule will short-circuit the demo. Keep the geo rule above any general allow.
</div>

## Where to find the exact steps

- [`setup/ravpn-config.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/ravpn-config.md) covers the VPN profile setup. The geolocation rule sits on top of that profile.
