---
layout: default
title: The helper scripts
permalink: /scripts/
eyebrow: Operate
summary: Six small scripts in the repo. Each one does a single chore so you do not have to think about it. None of them is required reading. They are here so the build runs in one afternoon, not three.
---

A "script" here is a small file of shell commands. You run it from the terminal. It does one job, prints what it is doing, and stops if anything goes wrong.

All six scripts live in [`scripts/`](https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/tree/{{ site.repo.branch }}/scripts) and are designed to be run from the top of the repo.

## What each script is for

<ul class="cards">
  <li>
    <a class="card" href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/scripts/preflight.sh">
      <span class="tag">Before deploy</span>
      <h3>preflight.sh</h3>
      <p>A health check for the laptop. Confirms that Terraform, the Azure CLI, and the rest of the tools are installed at versions the build needs, and that you are signed in to Azure. Run this before <code>terraform apply</code>.</p>
    </a>
  </li>
  <li>
    <a class="card" href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/scripts/bastion-tunnel.sh">
      <span class="tag">Admin access</span>
      <h3>bastion-tunnel.sh</h3>
      <p>Opens a private session through Azure Bastion to the firewall or the identity server. The session shows up as a port on your laptop, so you can SSH or open a browser to it locally as if the machine were on your desk.</p>
    </a>
  </li>
  <li>
    <a class="card" href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/scripts/generate-certs.sh">
      <span class="tag">Certificates</span>
      <h3>generate-certs.sh</h3>
      <p>Issues the public Let's Encrypt certificate that covers <code>vpn.rooez.com</code> and <code>trading.rooez.com</code>. The script proves you control those names by adding a temporary record at Cloudflare, the way Let's Encrypt's automated check works. The output is the firewall's identity certificate.</p>
    </a>
  </li>
  <li>
    <a class="card" href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/scripts/generate-app-cert.sh">
      <span class="tag">Certificates</span>
      <h3>generate-app-cert.sh</h3>
      <p>Generates the self-signed certificate used by the dashboard server. This is the certificate the firewall uses on the back-office connection between itself and the dashboard, not the one users see in their browser.</p>
    </a>
  </li>
  <li>
    <a class="card" href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/scripts/deploy-trading-app.sh">
      <span class="tag">App</span>
      <h3>deploy-trading-app.sh</h3>
      <p>Builds the React app on your laptop, copies it onto the dashboard server, copies the application certificate alongside it, and configures the web server (Nginx) to serve <code>/vpn</code> and <code>/ztaa</code>. Re-run it any time the React source changes.</p>
    </a>
  </li>
  <li>
    <a class="card" href="https://github.com/{{ site.repo.owner }}/{{ site.repo.name }}/blob/{{ site.repo.branch }}/scripts/smoke-test.sh">
      <span class="tag">Verify</span>
      <h3>smoke-test.sh</h3>
      <p>The end-of-build sanity check. Walks through every visible thing: DNS records, the firewall's public address, the identity server, both dashboard pages. Prints green for what works, red for what does not. The two checks it cannot run by itself are the user-facing sign-ins.</p>
    </a>
  </li>
</ul>

## The order they go in

```text
preflight.sh
   |
   v
terraform apply (in infra/)
   |
   v
generate-certs.sh         # firewall identity certificate
generate-app-cert.sh      # dashboard server certificate
   |
   v
bastion-tunnel.sh         # admin access for the next steps
   |
   v
deploy-trading-app.sh     # build and deploy the dashboard
   |
   v
smoke-test.sh             # final check
```

Each script is independent. Re-running one does not require re-running the others. The dashboard deploy is safe to run as many times as you like. Nothing in the scripts is destructive (none of them deletes anything).

## House rules

- Every script starts with `set -euo pipefail`. Plain English: stop on the first error, fail loudly when a variable is unset, and do not let a failure in the middle of a pipe go silent.
- Log lines are tagged `[INFO]`, `[WARN]`, or `[ERROR]`, so you can scan output quickly.
- Variables are quoted. Shell scripts that do not quote variables break in surprising ways when filenames contain spaces.
- No passwords, no API keys, no certificates are baked into any script. Where one is needed, the script reads it from an environment variable or a path the environment variable points at.

## When something fails

Read the log line. The scripts pass the underlying tool's output through unfiltered, so the actual error message from the Azure CLI, certbot, or npm is on screen. Most of the time, the fastest fix is to copy the failing command, run it by hand, and read what it says.
