---
layout: default
title: RAVPN Workshop
permalink: /
# Suppress the standard page-header. The hero section below renders the
# H1 and lede on the home page, so the layout's page-header would only
# duplicate them.
hide_page_header: true
---

<section class="hero">
  <div class="hero-inner">
    <p class="eyebrow" style="color: var(--cyan);">A one-day workshop</p>
    <h1>Two ways into one app, on the same firewall.</h1>
    <p class="lede">Picture someone on a hotel wifi who needs to reach a private dashboard at the office. The first way uses a VPN app. The second uses just a web browser. This workshop builds both, on a single firewall in Microsoft Azure, with everything you can show an audience in under an hour.</p>
    <div class="actions">
      <a class="btn btn-primary" href="{{ '/setup/' | relative_url }}">Start the build</a>
      <a class="btn btn-ghost" href="{{ '/architecture/' | relative_url }}">How it fits together</a>
      <a class="btn btn-accent" href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}">View on GitHub</a>
    </div>
  </div>
</section>

## What you'll see

Imagine a small trading firm. Their order entry dashboard sits on a private network inside Microsoft Azure. From the outside, the dashboard is invisible. A firewall is the only door in.

The same firewall offers two different ways through that door:

- **A VPN app on the laptop.** The user opens Cisco Secure Client (Cisco's VPN app), signs in with a password, and an encrypted tunnel forms between the laptop and the firewall. The dashboard loads. Close the app, the dashboard disappears.
- **A regular web browser, no app.** The user types the address into Chrome or Safari. The firewall hands them off to Microsoft to sign in. Microsoft asks for a phone push (the second factor in two-factor sign-in), confirms it, and the firewall forwards the user to the same dashboard.

Two doors, same building. Both running on one firewall. Both managed from one cloud dashboard. That is the demo.

## Why both doors

There is no single right answer to remote access. Some teams need full network access for a tunnel-aware app. Some only need one web app reached from a personal laptop. Letting an audience compare the two side by side, on the same kit, is the workshop.

| | VPN app | Browser only |
| --- | --- | --- |
| What the user installs | Cisco Secure Client | Nothing |
| What they sign in with | Password | Microsoft sign-in plus a phone push |
| What they can reach after sign-in | The whole network | One app |
| Best for | Power users, internal apps that need full network access | Contractors, BYOD laptops, single-app access |

## The five things to walk through

<ul class="cards">
  <li>
    <a class="card" href="{{ '/architecture/' | relative_url }}">
      <span class="tag">01 · Plan</span>
      <h3>How it fits together</h3>
      <p>The network, the firewall, the directory, the dashboard. What each piece is and what it actually does.</p>
    </a>
  </li>
  <li>
    <a class="card" href="{{ '/demos/' | relative_url }}">
      <span class="tag">02 · Show</span>
      <h3>The demos</h3>
      <p>The VPN, the browser-only zero trust path, a geographic policy switch, and the live management dashboard.</p>
    </a>
  </li>
  <li>
    <a class="card" href="{{ '/setup/' | relative_url }}">
      <span class="tag">03 · Build</span>
      <h3>Setup walkthrough</h3>
      <p>Six phases. Each one ends with a check. Read it top to bottom the first time.</p>
    </a>
  </li>
  <li>
    <a class="card" href="{{ '/scripts/' | relative_url }}">
      <span class="tag">04 · Operate</span>
      <h3>The helper scripts</h3>
      <p>Six small scripts that take care of the boring parts: certificates, deployment, smoke tests.</p>
    </a>
  </li>
  <li>
    <a class="card" href="{{ '/teardown/' | relative_url }}">
      <span class="tag">05 · Stop</span>
      <h3>Teardown</h3>
      <p>The big VMs are billed by the hour. When the workshop ends, take the environment down.</p>
    </a>
  </li>
</ul>

## A word on the two sign-in paths

The VPN demo asks for a password and nothing else. The browser-only demo asks for a password and then a phone push. Same user, same Microsoft account, two different outcomes.

That is intentional, and it comes down to a quirk of how passwords travel. The VPN uses an older protocol that sends the password to Microsoft directly, with no room in the conversation for a phone push. The browser path uses a newer protocol that hands the entire sign-in to Microsoft, including the second factor.

If you remember nothing else: the VPN path trades multi-factor for password compatibility, the browser path keeps multi-factor and gives up the tunnel. The workshop shows both because real environments use both.

<div class="callout callout-warning">
<strong>A note on cost.</strong>
The two main virtual machines in this build run on 8-CPU sizes. They are billed by the hour. A weekend of forgetting the demo is up will cost real money. The <a href="{{ '/teardown/' | relative_url }}">teardown page</a> has the exact steps to take it down.
</div>
