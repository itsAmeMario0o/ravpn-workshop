---
layout: default
title: Setup walkthrough
permalink: /setup/
eyebrow: Build
summary: Six phases. Each one ends with a check. Read it top to bottom the first time, then dip back in when something needs fixing.
---

## What you'll have at the end

A small environment running in one Microsoft Azure region. Inside it: a virtual Cisco firewall, an identity server, an admin side door, and a tiny web app. A user signs in through Cisco Secure Client and lands on the dashboard. Another user opens a browser, signs in to Microsoft with a phone push, and lands on the same dashboard. Both work. That is the workshop.

You do not need to be an expert in any of these products. You do need a few accounts:

- An Azure subscription where you have admin rights.
- A Cloudflare account managing one domain (this build uses `rooez.com`).
- A Cisco Smart Account with the right firewall and identity entitlements.
- A Cisco Security Cloud Control tenant with cdFMC already provisioned.

If any of those is missing, sort it out before starting. The build assumes all four exist.

## How the phases fit together

The work splits into six phases. The first phase is local: you set up tools, names, and certificates without touching Azure. Then Azure resources come up. Then the firewall and identity server are wired together. Then the two demos go live. Finally, you sign off.

Each phase ends with a Verify step. Do not move on until Verify passes. The most common cause of failure later is rushing past a Verify that looked almost done.

## Phase 1: Local setup

Nothing is in Azure yet. You are getting your laptop ready, getting the names and the certificates and the Microsoft side prepared, and pre-creating the firewall record in the cloud manager.

<div class="phase">
  <h3><span class="step-num">1</span> Prerequisites</h3>
  <p>Install the tools (Terraform, Azure CLI, Node.js, Python 3, certbot). Confirm the four accounts are real and you can sign in to each.</p>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/prerequisites.md">setup/prerequisites.md →</a></p>
</div>

<div class="phase">
  <h3><span class="step-num">2</span> Azure setup</h3>
  <p>Pick the region. Confirm your subscription has enough virtual CPU room for two 8-CPU machines. Click through the Marketplace acceptance for the Cisco firewall and identity server images. Without these acceptances, Terraform cannot start the machines.</p>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/azure-setup.md">setup/azure-setup.md →</a></p>
</div>

<div class="phase">
  <h3><span class="step-num">3</span> DNS</h3>
  <p>Create two DNS records at Cloudflare: <code>vpn.rooez.com</code> and <code>trading.rooez.com</code>. Use a placeholder IP for now. You'll update the IP after the firewall is up. Both records gray cloud (DNS only). The orange cloud breaks both demos.</p>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/dns-config.md">setup/dns-config.md →</a></p>
</div>

<div class="phase">
  <h3><span class="step-num">4</span> Certificates</h3>
  <p>Generate two certificates locally. The first is a free public Let's Encrypt certificate covering both names, used as the firewall's identity. The second is a self-signed certificate used by the dashboard server itself.</p>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/tls-certs.md">setup/tls-certs.md →</a></p>
</div>

<div class="phase">
  <h3><span class="step-num">5</span> Microsoft Entra</h3>
  <p>Add the custom domain to the directory. Create the demo user <code>trader1@rooez.com</code>. Register Microsoft Authenticator on a phone for that user. Create the Enterprise App for the browser-only demo. Create the App Registration that lets the identity server validate passwords.</p>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/entra-config.md">setup/entra-config.md →</a></p>
</div>

<div class="phase">
  <h3><span class="step-num">6</span> Pre-create the firewall record</h3>
  <p>In Cisco Security Cloud Control, create a pending firewall entry. Claim the licences. Save the registration key, the NAT ID, and the full <code>configure manager add</code> command. You'll paste that command into the firewall after it is up.</p>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/scc-onboarding.md">setup/scc-onboarding.md →</a></p>
</div>

## Phase 2: Stand up the platform

Azure resources come up.

<div class="phase">
  <h3><span class="step-num">7</span> Terraform deploy</h3>
  <p>Run Terraform from the <code>infra/</code> folder. It builds the network, the firewall, the dashboard server, and the secure side door. After it finishes, update the Cloudflare DNS records with the firewall's real public IP.</p>
  <p>The identity server is <strong>not</strong> built by Terraform. The Cisco identity server image fails Terraform's create path with a timeout error that has no good workaround. The next step deploys it through the Azure Portal instead.</p>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/terraform-deploy.md">setup/terraform-deploy.md →</a></p>
</div>

<div class="phase">
  <h3><span class="step-num">8</span> Identity server, in the Portal</h3>
  <p>Click through the Cisco identity server in the Azure Portal. Ten minutes of clicks. Then 45 to 60 minutes of waiting while it boots for the first time. Verify by running <code>show application status ise</code> through the side door.</p>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/ise-portal-deploy.md">setup/ise-portal-deploy.md →</a></p>
</div>

## Phase 3: Wire the security stack together

These are the parts that depend on each other. Order matters.

<div class="phase">
  <h3><span class="step-num">9</span> Register the firewall to the cloud manager</h3>
  <p>Connect to the firewall through the secure side door. Run <code>configure network management-data-interface</code>. This tells the firewall to talk to the cloud manager from its public-facing connection (the admin connection has no internet route). Then paste the <code>configure manager add</code> command from step 6. Wait for the firewall to appear as healthy in the cloud manager's inventory.</p>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/cdFMC-registration.md">setup/cdFMC-registration.md →</a></p>
</div>

<div class="phase">
  <h3><span class="step-num">10</span> Configure the identity server</h3>
  <p>In the identity server's web GUI: turn on the REST authentication service, create the identity store that points at Microsoft, register the firewall as an authorized client (and write down the shared secret you set), build the policy that says "if the password is good, allow the connection". Skip the verify step at the bottom of this guide for now. It depends on VPN configuration that comes in Phase 4.</p>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/ise-config.md">setup/ise-config.md →</a></p>
</div>

<div class="phase">
  <h3><span class="step-num">11</span> Upload certificates to the cloud manager</h3>
  <p>Three certificates, three different upload spots:</p>
  <ul>
    <li>The Let's Encrypt identity certificate goes under Devices &gt; Certificates as a PKCS12 file.</li>
    <li>The Microsoft signing certificate goes under Devices &gt; Certificates as Manual + CA Only.</li>
    <li>The self-signed application certificate goes under Objects &gt; PKI &gt; Internal Certs.</li>
  </ul>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/tls-certs.md">setup/tls-certs.md →</a></p>
</div>

## Phase 4: VPN, end to end

<div class="phase">
  <h3><span class="step-num">12</span> Build the VPN configuration</h3>
  <p>In the cloud manager, set up the connection from the firewall to the identity server (using the shared secret from step 10). Define the pool of IP addresses for connected users, the VPN connection profile, the rules that govern what the user can reach, and bind the firewall identity certificate. Deploy.</p>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/ravpn-config.md">setup/ravpn-config.md →</a></p>
</div>

<div class="phase">
  <h3><span class="step-num">13</span> Deploy the trading dashboard</h3>
  <p>Run <code>scripts/deploy-trading-app.sh</code>. The script builds the React app and pushes it (along with the dashboard server's certificate) onto the Ubuntu virtual machine. Both pages, <code>/vpn</code> and <code>/ztaa</code>, need to be live before any sign-in test will succeed.</p>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/scripts/deploy-trading-app.sh">scripts/deploy-trading-app.sh →</a></p>
</div>

<div class="phase">
  <h3><span class="step-num">14</span> Verify the VPN sign-in</h3>
  <p>Go back to the verify step from step 10 (<code>test aaa-server</code> from the firewall command line, through the side door). Once that passes, open Cisco Secure Client on a laptop, connect to <code>vpn.rooez.com</code> as <code>trader1@rooez.com</code>. The dark dashboard at <code>/vpn</code> loads.</p>
</div>

## Phase 5: Browser-only access, end to end

<div class="phase">
  <h3><span class="step-num">15</span> Build the browser-only configuration</h3>
  <p>In the cloud manager, set up the SAML server that points at Microsoft, define the Application Group for the trading dashboard, attach the identity certificate and the application certificate, write the per-app policy. Deploy.</p>
  <p><a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/ztaa-config.md">setup/ztaa-config.md →</a></p>
</div>

<div class="phase">
  <h3><span class="step-num">16</span> Verify the browser-only sign-in</h3>
  <p>Open a browser. Visit <code>https://trading.rooez.com/ztaa</code>. The page redirects to Microsoft. Sign in. Approve the phone push. The browser returns to the light dashboard.</p>
</div>

## Phase 6: Sign-off

<div class="phase">
  <h3><span class="step-num">17</span> Live management view</h3>
  <p>Open the cloud manager. The active VPN session is on the live dashboard with the user's name, source IP, country, and Cisco app version.</p>
</div>

<div class="phase">
  <h3><span class="step-num">18</span> Smoke test</h3>
  <p>Run <code>scripts/smoke-test.sh</code>. All checks green except the two that cannot be run automatically: the actual Cisco app sign-in (which needs a human laptop) and the actual browser sign-in (which needs a human phone).</p>
</div>

## Things that catch people out

<div class="callout callout-warning">
<strong>Two sign-in flows, one user, two outcomes.</strong>
The VPN demo has no phone push because the protocol cannot carry one. The browser-only demo has a phone push because the protocol can. Mixing them up, or expecting the same behaviour from both, is the most common confusion.
</div>

<div class="callout callout-warning">
<strong>The firewall's admin connection has no public IP.</strong>
Azure Bastion is the only way in for an admin. The cloud manager registration also does not go through that connection. Run <code>configure network management-data-interface</code> on the firewall before pasting the registration command.
</div>

<div class="callout callout-warning">
<strong>Cloudflare must stay gray.</strong>
The cloud icon next to the DNS record is gray (DNS only) by default and turns orange when you click it (proxied). Orange breaks both demos. Click it back to gray.
</div>

<div class="callout callout-danger">
<strong>The "AppGroupName" placeholder is literal.</strong>
Microsoft and the cloud manager both reference an Entity ID and a callback URL that contain the literal text <code>[AppGroupName]</code>. Replace it with the same value in both places before testing the browser-only demo.
</div>

<div class="callout callout-warning">
<strong>Three certificates, three sources, three upload spots.</strong>
The identity certificate (public, from Let's Encrypt), the Microsoft signing certificate (download it from the Microsoft federation metadata XML file), and the application certificate (self-signed, generated locally) each land in a different spot in the cloud manager. The table is in <a href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/tls-certs.md">tls-certs.md</a>.
</div>

## Reference

- [`setup/bastion-access.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/bastion-access.md). How to use the secure side door (Azure Bastion).
- [`setup/ztaa-extensions.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/setup/ztaa-extensions.md). How to extend the browser-only pattern to the identity server's admin GUI and other internal web apps.
- [`LESSONS-LEARNED.md`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/LESSONS-LEARNED.md). Every gotcha hit during the original build, with the fix.
