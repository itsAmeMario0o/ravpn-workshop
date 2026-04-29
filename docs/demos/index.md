---
layout: default
title: The demos
permalink: /demos/
eyebrow: Show
summary: Four short scenes you can run in front of an audience, plus one whiteboard moment for the future.
---

The workshop runs in a clean order. Each demo has one thing it is trying to prove. The point is not how clever the technology is. The point is that an audience watching for ten minutes can see what changed.

<ul class="cards">
  <li>
    <a class="card" href="{{ '/demos/ravpn/' | relative_url }}">
      <span class="tag">Demo 1</span>
      <h3>VPN sign-in</h3>
      <p>A trader on a hotel wifi opens the VPN app, signs in, and lands on the dashboard. Close the app, the dashboard is gone.</p>
    </a>
  </li>
  <li>
    <a class="card" href="{{ '/demos/geolocation/' | relative_url }}">
      <span class="tag">Demo 2</span>
      <h3>Different rules by location</h3>
      <p>The same firewall treats two clients differently based on where they are connecting from. Visible on a live map.</p>
    </a>
  </li>
  <li>
    <a class="card" href="{{ '/demos/ztaa/' | relative_url }}">
      <span class="tag">Demo 3</span>
      <h3>Browser-only access with phone push</h3>
      <p>No app installed. Just a browser, a Microsoft sign-in, and a phone push. The user lands on the same dashboard.</p>
    </a>
  </li>
  <li>
    <a class="card" href="{{ '/demos/cdfmc-dashboard/' | relative_url }}">
      <span class="tag">Demo 4</span>
      <h3>The live management view</h3>
      <p>Live sessions, the user's location on a map, and the version of the VPN app they are running. All in one screen.</p>
    </a>
  </li>
  <li>
    <a class="card" href="{{ '/demos/multi-instance/' | relative_url }}">
      <span class="tag">Whiteboard</span>
      <h3>Multiple firewalls in one box</h3>
      <p>Not deployed. A short conversation about running several firewalls inside one piece of Cisco hardware.</p>
    </a>
  </li>
</ul>

## The proof for each one

The build is finished when every line below is true.

| Demo | The thing that proves it works |
| --- | --- |
| VPN sign-in | The user `trader1@rooez.com` connects to `vpn.rooez.com` from the Cisco app and the dark dashboard at `/vpn` loads. Without the tunnel, that page is unreachable. |
| Different rules by location | A second connection profile applies a location-based rule. The management dashboard shows the user's country and the rule that fired. |
| Browser-only access | Visiting `https://trading.rooez.com/ztaa` redirects to Microsoft, asks for the password and the phone push, then returns the user to the light dashboard. No VPN app at any point. |
| The live management view | The active VPN session is visible in the cloud manager: username, source IP, country, and VPN app version. |
| Multiple firewalls in one box | A whiteboard slide is ready. Nothing is deployed. |
