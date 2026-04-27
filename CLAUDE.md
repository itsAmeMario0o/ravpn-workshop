# RAVPN Workshop

Claude Code instructions for the Azure FTDv RAVPN workshop build repo.

---

## Design principle: simplicity

This project must be built in 24 hours. Optimize for readable code, flat structure, and fewer files. No abstraction for its own sake. No premature generalization. If a single script does the job, do not split it into a module. If two related resources fit in one file, leave them there.

When deciding between two approaches, pick the one a stranger could read end-to-end in under a minute.

For the canonical architecture details, see `azure-demo-plan.md` (workspace root). This file is the operational guide, not the source of truth on the design.

---

## What this repo builds

A single-site Azure demo environment for the RAVPN workshop. Four live demos, one conceptual overview.

**RAVPN:** Secure Client connects to FTDv, authenticates through ISE (RADIUS) backed by Microsoft Entra ID (REST ID/ROPC). User reaches a fictitious trading dashboard (dark theme, `/vpn` route). Tunnel required for access.

**Geolocation VPN:** Policy-based tunnel steering by client geographic location. Two connection profiles on FTDv, geo-based access control rules in cdFMC, visual confirmation on the VPN dashboard geographic view.

**ZTAA (Zero Trust Application Access):** Browser-based, no VPN client. FTD intercepts HTTPS, redirects to Entra ID SAML, user authenticates with MFA (Microsoft Authenticator push). FTD brokers the connection to the trading dashboard (light theme, `/ztaa` route). Per-app scoped access, SAML-only, no RADIUS.

**cdFMC VPN dashboard:** Real-time session monitoring, connection analytics, tunnel status, geographic distribution, Secure Client version inventory. Passive demo element during active RAVPN sessions.

**Multi-instance (conceptual):** Not deployed. Whiteboard discussion covering FTD multi-instance on Firepower 4100/4200 for workload isolation and blue-green upgrades. Presented as a future use case for multi-tenant VPN architectures.

---

## Architecture

```
Internet
   |
   v
+----------------------------------------------------------------------+
|  Azure VNet: 10.100.0.0/16                                           |
|                                                                       |
|  FTDv (Standard_D8s_v3, 8 vCPU, 32 GB, FTDv5 tier)                  |
|    Nic0: management  10.100.0.10  private only (Bastion + sftunnel)  |
|    Nic1: diagnostic   10.100.1.10                                     |
|    Nic2: outside      10.100.2.10  pip-ftdv-outside (RAVPN + ZTAA)   |
|    Nic3: inside       10.100.3.10                                     |
|                                                                       |
|  Trading App (Ubuntu B1s, 10.100.3.20)                               |
|    React/Vite SPA, two themes by route: /vpn dark, /ztaa light       |
|    Nginx serves static build + self-signed cert for ZTAA backend TLS |
|                                                                       |
|  ISEv (Standard_D8s_v4, 8 vCPU, 32 GB, PSN-only, ISE 3.5)          |
|    10.100.4.10, identity subnet                                       |
|    REST ID > Entra ID (ROPC) for RAVPN auth                          |
|                                                                       |
|  Azure Bastion (Standard SKU, PaaS)                                  |
|    SSH tunnel to ISE GUI and FTD management                           |
|    No public IP on ISE or trading app                                 |
+----------------------------------------------------------------------+
         |
         v
   cdFMC via Security Cloud Control (SaaS, FTDv pre-registered)
```

**Subnets:** management (10.100.0.0/24), diagnostic (10.100.1.0/24), outside (10.100.2.0/24), inside (10.100.3.0/24), identity (10.100.4.0/24), AzureBastionSubnet (10.100.5.0/26).

**DNS:** `vpn.rooez.com` and `trading.rooez.com` both resolve to FTD outside public IP. Cloudflare A records, DNS only (gray cloud). TLS: Let's Encrypt SAN cert for both hostnames via DNS-01/Cloudflare.

**Auth flows:** RAVPN = FTD > ISE (RADIUS) > Entra ID (REST ID/ROPC). ZTAA = FTD > Entra ID (SAML direct + MFA).

**Management plane:** The FTDv management interface has no public IP. Admin access is via Azure Bastion. For cdFMC sftunnel registration, configure FTDv to source management traffic from a data interface (outside) using `configure network management-data-interface`. This is the supported path when the management NIC has no Internet egress.

---

## Components

| Component | Role | Key detail |
|---|---|---|
| FTDv | Firewall, RAVPN termination, ZTAA enforcement | FTD 10.x on Standard_D8s_v3 (smallest Dsv3 size that supports the 4 NICs FTDv requires). Day-0 bootstrap via Custom Data JSON. Registered to cdFMC through SCC. |
| cdFMC | Centralized management | SaaS via Security Cloud Control. All FTD policy config happens here. |
| ISEv | RADIUS server for RAVPN | PSN-only (Extra Small) on Standard_D8s_v4. SSH key auth on the underlying Linux iseadmin user (matches Cisco's official Terraform pattern); ISE GUI and ISE CLI use the password from `terraform.tfvars`. REST ID identity source pointing to Entra ID. Validates credentials via ROPC. |
| Azure Bastion | Secure admin access | Standard SKU. SSH tunnel to ISE and FTD management. No jump host VM needed. |
| Entra ID | Identity provider | SAML IdP for ZTAA (with MFA). OAuth ROPC target for ISE REST ID. Free with Azure subscription. |
| Trading App | Demo target application | React/Vite SPA on Ubuntu B1s. Dark theme at `/vpn`, light theme at `/ztaa`. Nginx reverse proxy. |

---

## Project structure

```
ravpn-workshop/
|
+-- CLAUDE.md                    <-- This file
+-- .gitignore
+-- .gitleaks.toml               <-- Custom gitleaks config
+-- .pre-commit-config.yaml
+-- .github/
|   +-- workflows/
|   |   +-- quality.yaml         <-- CI: lint, test, security scan
|   |   +-- pages.yaml           <-- GitHub Pages deploy
|   +-- dependabot.yml
|
+-- docs/                        <-- DEFERRED: GitHub Pages source (Jekyll)
|   +-- _config.yml
|   +-- index.md
|   +-- ravpn.md
|   +-- ztaa.md
|   +-- geolocation.md
|   +-- multi-instance.md
|   +-- automation.md
|
+-- docs/specs/                  <-- DEFERRED: Feature specs
|   +-- ravpn.md
|   +-- ztaa.md
|   +-- trading-app.md
|   +-- bastion-access.md
|
+-- setup/                       <-- Beginner walkthrough
|   +-- README.md                <-- Step-by-step setup guide
|   +-- prerequisites.md         <-- Tool versions, accounts, access
|   +-- azure-setup.md           <-- Subscription, resource limits, region
|   +-- cdFMC-registration.md    <-- SCC + cdFMC device registration
|   +-- entra-config.md          <-- Demo users, app registrations, MFA
|   +-- ise-config.md            <-- REST ID, NAD, auth/authz policies
|   +-- tls-certs.md             <-- Let's Encrypt + Cloudflare DNS-01
|   +-- dns-config.md            <-- Cloudflare A records
|
+-- infra/                       <-- Terraform (Azure resources)
|   +-- main.tf
|   +-- variables.tf
|   +-- outputs.tf
|   +-- terraform.tfvars.example
|   +-- versions.tf              <-- Provider version pins
|   +-- modules/
|   |   +-- network/             <-- VNet, subnets, NSGs, UDRs
|   |   +-- ftdv/                <-- FTDv VM, NICs, PIPs, Custom Data
|   |   +-- ise/                 <-- ISEv VM, NIC
|   |   +-- app/                 <-- Trading app VM, NIC, cloud-init
|   |   +-- bastion/             <-- Azure Bastion, public IP, subnet
|
+-- scripts/                     <-- Deployment and utility scripts
|   +-- deploy-trading-app.sh    <-- Nginx, React build, two-route config
|   +-- generate-certs.sh        <-- Let's Encrypt SAN cert generation
|   +-- bastion-tunnel.sh        <-- az network bastion tunnel helper
|
+-- app/                         <-- Trading dashboard (React/Vite)
|   +-- package.json
|   +-- vite.config.ts
|   +-- tsconfig.json
|   +-- src/
|   |   +-- App.tsx
|   |   +-- main.tsx
|   |   +-- routes/
|   |   |   +-- VpnDashboard.tsx     <-- Dark theme
|   |   |   +-- ZtaaDashboard.tsx    <-- Light theme
|   |   +-- components/
|   |   +-- hooks/
|   |   +-- types/
|   +-- public/
|   +-- tailwind.config.ts
|
+-- automation/                  <-- DEFERRED: Post-deploy config wrappers
|   +-- python/
|   |   +-- requirements.txt
|   |   +-- fmc_client.py        <-- FMC REST API wrapper
|   |   +-- ise_client.py        <-- ISE ERS API wrapper
|   +-- powershell/
|   |   +-- Invoke-FmcApi.ps1
|   |   +-- Invoke-IseApi.ps1
```

Items marked **DEFERRED** are not part of the 24-hour build. See "24-hour build priority" below.

---

## 24-hour build priority

Three tiers. If a tier-1 item is not done, no tier-2 work begins. Tier-3 items do not block the workshop.

**Must-ship (tier 1):**
- Terraform under `infra/` (network, FTDv, ISE, Bastion, trading app VM)
- Trading dashboard app (`app/`) with `/vpn` and `/ztaa` routes
- Deployment scripts (`scripts/`) for app deploy and TLS cert
- Setup guides (`setup/`) covering prerequisites, Azure, DNS/TLS, Entra, cdFMC, ISE

**Should-ship (tier 2):**
- `.pre-commit-config.yaml` with gitleaks and terraform_fmt
- `.github/workflows/quality.yaml` with terraform fmt/validate and gitleaks

**Defer (tier 3, post-workshop):**
- `docs/` GitHub Pages site and `pages.yaml` workflow
- `docs/specs/` formal feature specs
- `automation/` Python and PowerShell API wrappers
- `tfsec`, frontend lint/test jobs in CI, dependabot

---

## Definition of done

Each workshop demo block maps to a single testable condition. The build is done when all of these pass.

| Demo block | Condition |
|---|---|
| RAVPN | `trader1@rooez.com` connects via Secure Client to `vpn.rooez.com`, authenticates through ISE, lands on the dark `/vpn` dashboard. Without the tunnel, `/vpn` is unreachable. |
| Geolocation VPN | A second connection profile applies a geo-based access control rule. The cdFMC dashboard shows the client's geographic origin. |
| ZTAA | Browser to `https://trading.rooez.com/ztaa` redirects to Entra ID, prompts for MFA, returns to the light `/ztaa` dashboard. No VPN client involved. |
| cdFMC VPN dashboard | Active RAVPN session is visible in cdFMC with username, source IP, geographic location, and Secure Client version. |
| Multi-instance | Whiteboard slide ready. No deployment needed. |

---

## Setup walkthrough

The `setup/` folder contains a step-by-step guide for building this environment from scratch. Written for someone who has not deployed FTDv or ISE on Azure before.

**Sequence:**

1. **Prerequisites** (`prerequisites.md`): Install Terraform, Azure CLI, Node.js, Python 3, certbot. Confirm Azure subscription, Cisco Smart Account, SCC tenant with cdFMC.
2. **Azure setup** (`azure-setup.md`): Select region, confirm resource quotas (vCPU limits for Dsv3 and Dsv4), accept Marketplace terms for FTDv and ISEv images.
3. **Terraform deploy** (`infra/`): Copy `terraform.tfvars.example` to `terraform.tfvars`, fill in values, run `terraform init && terraform plan && terraform apply`.
4. **DNS and TLS** (`dns-config.md`, `tls-certs.md`): Create Cloudflare A records for `vpn.rooez.com` and `trading.rooez.com`. Generate Let's Encrypt SAN cert.
5. **Entra ID** (`entra-config.md`): Add `rooez.com` custom domain, create demo user `trader1@rooez.com`, register Microsoft Authenticator, create Enterprise App for ZTAA SAML, create App Registration for ISE REST ID.
6. **cdFMC registration** (`cdFMC-registration.md`): SSH into FTDv through Bastion, paste `configure manager add` command from SCC.
7. **ISE config** (`ise-config.md`): Configure REST ID identity source, add FTDv as NAD, build auth/authz policies.
8. **Trading app** (`deploy-trading-app.sh`): Build React app, deploy to nginx on Ubuntu VM.

Each step lists what to verify before moving to the next step. If a verification fails, the guide explains what went wrong and how to fix it.

---

## .gitignore

The repo `.gitignore` must include at minimum:

```
# Terraform
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl
*.tfvars
!terraform.tfvars.example
crash.log

# Secrets and credentials
*.pem
*.key
*.crt
*.pfx
*.p12
.env
.env.*
cloudflare.ini
**/secrets/
**/credentials/

# Python
__pycache__/
*.pyc
.venv/
venv/
*.egg-info/

# Node
node_modules/
dist/
.vite/
*.tsbuildinfo

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Build artifacts
*.zip
*.tar.gz
```

---

## Terraform state

Local state only. No remote backend. This is a demo environment on a single developer's machine.

```hcl
# No backend block needed. Terraform defaults to local state.
# State file: terraform.tfstate in infra/ directory.
# Do NOT commit state files. They contain sensitive values.
```

---

## NSG rules for demo access

The FTD outside interface and Azure Bastion must accept connections from unknown source IPs (Mario's current IP is not static). Configure these NSGs with `0.0.0.0/0` source for the demo period:

| NSG | Rule | Source | Destination port | Note |
|---|---|---|---|---|
| nsg-outside | Allow-RAVPN | 0.0.0.0/0 | TCP 443, UDP 443, UDP 500, UDP 4500 | Secure Client and DTLS |
| nsg-outside | Allow-Sftunnel | 0.0.0.0/0 | TCP 8305 outbound | cdFMC sftunnel sourced from the data interface (see Management plane note) |
| AzureBastionSubnet NSG | Per Azure Bastion requirements | Various | Various | Follow Microsoft docs for Bastion NSG rules |

The management interface has no public IP and no inbound NSG rules from the Internet. Admin access is via Bastion only. cdFMC sftunnel egress comes from the outside (data) interface, not the management interface.

After the demo, restrict source IPs or tear down the environment entirely.

---

## Naming conventions and tags

**Resource names:** lowercase, hyphen-separated, prefixed by resource type. Pattern: `<type>-<role>[-<index>]`.

Examples:
- `vnet-demo`
- `nsg-outside`, `nsg-inside`, `nsg-mgmt`
- `pip-ftdv-outside`
- `vm-ftdv`, `vm-ise`, `vm-tradingapp`
- `nic-ftdv-mgmt`, `nic-ftdv-outside`
- `bastion-demo`

**Tags:** apply to every resource at the resource group or module level. Required tags:

| Tag | Value |
|---|---|
| project | `ravpn-demo` |
| environment | `demo` |
| owner | `mario` |

All three are hardcoded in the `locals` block in `infra/main.tf`. Do not include a `demo-date` tag. The repo is reused across workshops, and a date would just go stale.

---

## Skills

Skills are available in this session but **not preloaded into context**. Invoke each skill at the start of the work block it covers. Pre-firing all of them dumps thousands of tokens of playbook for work you have not started.

Skill IDs use the form `<plugin>:<skill>`. Bare names (e.g., `humanizer`, `simplify`, `security-review`) are built-in.

**Installed plugins:**
- `andrej-karpathy-skills` (from `forrestchang/andrej-karpathy-skills`)
- `engineering-skills` and `engineering-advanced-skills` (from `alirezarezvani/claude-skills`)
- `sales-skills` (from `louisblythe/Sales-Skills`)

The two `alirezarezvani/claude-skills` plugins ship with a broken `plugin.json` (`"skills": "./"`). The local manifests have been patched to enumerate each skill. If `/plugin marketplace update` is run, re-apply the same patch — the script lives at `scripts/fix-claude-skills-plugins.sh` (or the inline Python under `~/.claude/`).

### Coding mindset (apply throughout)

- `andrej-karpathy-skills:karpathy-guidelines` — surgical changes, no overcomplication. Matches the simplicity design principle.
- `simplify` — post-implementation review for reuse, quality, efficiency. Run when a module hits functional-complete.

### Infrastructure (Terraform, Azure)

- `engineering-advanced-skills:terraform-patterns` — module structure, variable/output conventions, provider pinning. Invoke when opening `infra/`.
- `engineering-skills:azure-cloud-architect` — Azure architecture, networking, naming, tagging. Invoke when designing the network module.
- `engineering-skills:cloud-security` — NSG misconfigs, IAM, public exposure checks. Invoke before `terraform apply`.

### Frontend (React, TypeScript, Tailwind)

- `engineering-skills:senior-frontend` — React component patterns, hooks, Tailwind, perf. Invoke when opening `app/`.

### CI and pipelines

- `engineering-advanced-skills:ci-cd-pipeline-builder` — GitHub Actions structure, job deps, secret handling. Invoke when writing `.github/workflows/quality.yaml`.

### Review and security

- `engineering-skills:code-reviewer` — TS/JS/Python PR review with risk scoring. Invoke after each tier-1 deliverable.
- `engineering-skills:adversarial-reviewer` — second-opinion review. Invoke before declaring the build done.
- `engineering-advanced-skills:self-eval` — honest work-quality scoring. Invoke alongside the verification checklist.
- `security-review` — pending-branch security review. Invoke before exposing the FTDv outside interface to the Internet.
- `engineering-skills:senior-secops` — secure-dev practices for the FTDv outside interface and any public surface.

### Writing and documentation

- `humanizer` — strip AI-writing tells. Apply to every doc, setup guide, and commit body before committing.

### Backend / Python (deferred work only)

- `engineering-skills:senior-backend` — Python REST API client patterns (FMC/ISE wrappers). Only relevant if `automation/` ships (tier-3).

### Sales context (narrative only, not code)

`sales-skills:*` informs the documentation narrative for the deferred Jekyll site. Not code skills. Useful examples when that work resumes: `sales-skills:storytelling`, `sales-skills:competitive-positioning`, `sales-skills:building-rapport`.

---

## Pre-commit hooks

Install `pre-commit` and configure `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks:
      - id: gitleaks

  - repo: https://github.com/antonbabenko/pre-commit-tf
    rev: v1.96.1
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tfsec

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: detect-private-key
      - id: check-added-large-files
        args: ['--maxkb=500']
      - id: check-yaml
      - id: check-json
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-merge-conflict
```

### Custom gitleaks config

Create `.gitleaks.toml` at the repo root:

```toml
title = "RAVPN Workshop - Gitleaks Config"

[allowlist]
description = "Allowlisted patterns"
paths = [
  '''terraform\.tfvars\.example''',
  '''setup/.*\.md''',
]

[[rules]]
id = "cisco-reg-key"
description = "Cisco registration key"
regex = '''(?i)(reg[-_]?key|registration[-_]?key)\s*[=:]\s*['"]?[\w-]{8,}'''
tags = ["cisco", "credential"]

[[rules]]
id = "azure-client-secret"
description = "Azure client secret"
regex = '''(?i)(client[-_]?secret|AZURE_CLIENT_SECRET)\s*[=:]\s*['"]?[\w~.-]{30,}'''
tags = ["azure", "credential"]

[[rules]]
id = "cloudflare-api-token"
description = "Cloudflare API token"
regex = '''(?i)(cloudflare[-_]?api[-_]?token|dns_cloudflare_api_token)\s*[=:]\s*['"]?[\w-]{30,}'''
tags = ["cloudflare", "credential"]
```

### GitHub Secret Protection

Enable GitHub Secret Protection (formerly Secret Scanning) in repo settings. This catches secrets that bypass pre-commit (direct GitHub UI edits, API pushes).

---

## GitHub Actions

### quality.yaml

Runs on every push and pull request:

```yaml
name: Quality

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform fmt -check -recursive
        working-directory: infra
      - run: terraform init -backend=false
        working-directory: infra
      - run: terraform validate
        working-directory: infra

  tfsec:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aquasecurity/tfsec-action@v1.0.3
        with:
          working_directory: infra

  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: gitleaks/gitleaks-action@v2

  python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install -r automation/python/requirements.txt
      - run: python -m pytest automation/python/ -v

  frontend:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: app
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npx tsc --noEmit
      - run: npx eslint src/ --max-warnings 0
      - run: npx prettier --check src/
      - run: npx vitest run
```

### pages.yaml

Deploys `docs/` to GitHub Pages using Jekyll:

```yaml
name: Deploy Pages

on:
  push:
    branches: [main]
    paths: ['docs/**']

permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v4
      - uses: actions/jekyll-build-pages@v1
        with:
          source: docs
      - uses: actions/upload-pages-artifact@v3

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

### dependabot.yml

```yaml
version: 2
updates:
  - package-ecosystem: "terraform"
    directory: "/infra"
    schedule:
      interval: "weekly"
  - package-ecosystem: "npm"
    directory: "/app"
    schedule:
      interval: "weekly"
  - package-ecosystem: "pip"
    directory: "/automation/python"
    schedule:
      interval: "weekly"
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

---

## GitHub Pages (Jekyll)

The `docs/` folder is the source for a Jekyll site deployed to GitHub Pages. This is the public-facing documentation site for the PoV.

**Purpose:** Host demo documentation, RAVPN notes, multi-instance notes, automation notes. Link to Cisco documentation as supporting references. Provide a reference site the audience can bookmark.

### Jekyll config (`docs/_config.yml`)

```yaml
title: RAVPN Workshop
description: FTDv Remote Access VPN demo environment documentation
theme: minima
baseurl: "/ravpn-workshop"
url: ""
markdown: kramdown
plugins:
  - jekyll-seo-tag
```

### Page structure

Each page follows a consistent structure: what the feature is, why it matters, how the demo proves it. Apply the humanizer skill and writing standards to all page content before committing.

---

## Code quality standards

Readability beats cleverness. Simplicity beats flexibility. A 24-hour build cannot afford abstractions that pay off later. Write the obvious version first. If you find yourself adding a layer "in case we need it," delete that layer.

Concrete defaults:

- Flat over nested. One file with three related functions beats three files with one function each.
- Inline beats indirection. If a helper is called once, leave the code in place.
- No premature interfaces, no premature config knobs, no premature factories.
- A reader should understand any single file end-to-end without jumping between modules.
- If you reach for a design pattern, justify it in a comment. If you cannot justify it, remove it.

### Comment style for this repo

This is a workshop demo. Reviewers and attendees may have zero prior exposure to FTDv, ISE, Azure, or even Terraform. Override the usual "default to no comments" rule and comment generously.

Three principles, all of them mandatory:

1. **Plain language.** Short sentences, active voice, no jargon without a definition on first use. If a term is Cisco-specific, FTDv-specific, or Azure-specific, define it the first time it appears in the file.
2. **Zero knowledge assumed.** Write as if the reader has never deployed FTDv, never used Terraform, and never seen this codebase. Explain what each block does and why the choice was made, not just what the next line of code is.
3. **Humanizer-cleaned.** No AI-writing tells. Specifically: no "leverage", "utilize", "comprehensive", "seamless", "robust", "cutting-edge", "pivotal", "delve", "tapestry", "stands as", "serves as", "underscores", "highlights its importance", em-dashes, curly quotes, or rule-of-three filler. The same forbidden list as the Writing standards section above. If a sentence sounds like it was generated, rewrite it.

Each file gets a header that says what it is and why it exists. Each non-obvious resource or block gets a short inline comment explaining the choice. Tone matches the setup guides: simple, direct, accessible.

This applies to every commented file in the repo, including future commits. If you are adding code or changing a file that has comments, match the existing voice. If a file has no comments yet, add them following these rules.

### Python

- PEP 8 compliance. Use `ruff` for linting and formatting.
- Type hints on all function signatures. Use `from __future__ import annotations` for forward references.
- Maximum 30 lines per function. If a function exceeds 30 lines, extract helper functions.
- Docstrings on all public functions. Google style.
- No hardcoded credentials. Use environment variables or vault retrieval at runtime.
- `requirements.txt` pinned to exact versions.
- Tests in the same directory structure, prefixed with `test_`.

### React/TypeScript

- Functional components only. No class components.
- TypeScript strict mode. No `any` types except where interfacing with untyped libraries (document the exception).
- Tailwind CSS for styling. No CSS modules, no styled-components.
- Component files: one component per file, named to match the export.
- Props interfaces defined in the same file as the component, above the component definition.
- Hooks in `hooks/` directory. Custom hooks prefixed with `use`.
- No `localStorage` or `sessionStorage` (not supported in some rendering contexts).
- Vitest for unit tests. Test files colocated with source files (`Component.test.tsx`).

### Terraform

- Pin provider versions in `versions.tf`. Use `~>` for minor version flexibility.
- Pin module versions if using registry modules.
- One resource per logical concern. Do not pack unrelated resources into a single file.
- Use `locals` for repeated values. Do not repeat strings across resources.
- `snake_case` for all resource names, variable names, and output names.
- Variables: always include `description` and `type`. Include `default` only when a sensible default exists. Sensitive variables marked with `sensitive = true`.
- Outputs: include `description`. Mark sensitive outputs.
- Module structure: `main.tf`, `variables.tf`, `outputs.tf` in every module.
- No inline blocks when a separate resource exists (example: use `azurerm_network_security_rule` instead of inline `security_rule` blocks in `azurerm_network_security_group`).
- `terraform fmt` must pass with no changes.
- `terraform validate` must pass.
- `tfsec` must pass with no high or critical findings.

### Shell scripts

- Bash with `set -euo pipefail` at the top of every script.
- ShellCheck clean. No warnings.
- Functions for reusable logic. No inline blocks longer than 20 lines without extraction.
- Log what the script is doing. Use `echo` with prefixes: `[INFO]`, `[WARN]`, `[ERROR]`.
- Quote all variables. No unquoted expansions.

---

## Writing standards

All documentation, README content, setup guides, commit messages, and GitHub Pages content must follow the workspace writing standards:

- Short sentences. Active voice.
- No em-dashes. Use a comma, period, or rewrite.
- No filler phrases: "it is important to note," "in order to," "moving forward."
- No inflated language: "pivotal," "transformative," "cutting-edge," "leverage," "utilize."
- No empty modifiers: "very," "really," "extremely," "quite."
- Lead with the point. State what matters first. Context follows.
- Spell out acronyms on first use.

Apply the humanizer skill to all documentation before committing. Read the output aloud. If it sounds like it was written by an AI, rewrite it.

---

## Commit message format

Simple type-prefixed subject. Body optional, separated by a blank line.

```
<type>: <short description>

<optional body>
```

**Types:** `feat`, `fix`, `infra`, `docs`, `chore`, `test`.

`infra` is its own type, not a scope. Anything that touches `infra/` (Terraform, modules, providers) takes this type. `feat` is for application code, `fix` for bug fixes, `docs` for guides and READMEs, `chore` for tooling/CI/repo plumbing, `test` for test additions.

Examples:

```
infra: add FTDv and ISEv Terraform modules
feat: trading app with dual theme routes
fix: correct NSG rule for sftunnel port
docs: add ISE REST ID setup guide
chore: add gitleaks pre-commit hook
```

Subject under 72 characters. Imperative mood. No trailing period. No issue references — this is a demo repo, not a product.

---

## Azure Marketplace images

### FTDv

- Publisher: `cisco`
- Offer: `cisco-ftdv`
- Plan: `cisco-ftdv-x86-byol` or `cisco-ftdv-x86-payg` (FTD 10.x SKUs; the older `ftdv-azure-byol`/`ftdv-azure-payg` SKUs only publish 7.x and earlier)
- Accept terms: `az vm image terms accept --publisher cisco --offer cisco-ftdv --plan cisco-ftdv-x86-byol`
- Custom Data: JSON, base64-encoded. Fields: AdminPassword, Hostname, ManageLocally (No), Diagnostic (OFF), FmcIp (DONTRESOLVE), FmcRegKey, FmcNatId. The FmcIp field is named exactly that in 10.x (not FmcIpAddress). FirewallMode is not a documented 10.x customData field.
- NIC order is fixed: Nic0=Management, Nic1=Gi0/0 (diagnostic), Nic2=Gi0/1 (outside), Nic3=Gi0/2 (inside).
- VM generation: Gen 1 only.
- FTD 10.x requires Dsv3 or Fsv2 families. Dv2 is not supported on 10.x.

### ISEv

- Publisher: `cisco`
- Offer: `cisco-ise-virtual`
- Plan: `cisco-ise_3_5` (3.4 also available; 3.5 is current as of this writing)
- Accept terms: `az vm image terms accept --publisher cisco --offer cisco-ise-virtual --plan cisco-ise_3_5`
- User Data: key=value plaintext, base64-encoded. Fields: hostname, primarynameserver (168.63.129.16), dnsdomain, ntpserver, timezone, password, ersapi=yes, openapi=yes, pxGrid=yes, pxgrid_cloud=yes.
- Standard_D8s_v4 for Extra Small PSN-only deployment.
- 300 GB minimum disk.

---

## Sensitive values

Never commit these. Store in `terraform.tfvars` (gitignored) or retrieve from environment variables at runtime:

- Azure subscription ID, tenant ID, client ID, client secret
- FTDv admin password
- cdFMC registration key and NAT ID
- ISE admin password
- Entra App Registration client secret (for ISE REST ID)
- Cloudflare API token
- Let's Encrypt account key

The `terraform.tfvars.example` file documents every required variable with placeholder values and descriptions. Copy it, fill in real values, never commit the copy.

---

## Reference repos

- [CiscoDevNet/cisco-ftdv](https://github.com/CiscoDevNet/cisco-ftdv): ARM templates for FTDv on Azure. Reference for NIC ordering and Day-0 JSON schema.
- [CiscoISE/ciscoise-terraform-automation-azure-nodes](https://github.com/CiscoISE/ciscoise-terraform-automation-azure-nodes): Official ISE Terraform module for Azure.
- [galafis/trading-dashboard](https://github.com/galafis/trading-dashboard): Inspiration for the trading dashboard app. React 19, Vite 6, Tailwind CSS, Recharts, Lucide React.
- [CiscoDevNet/terraform-provider-fmc](https://github.com/CiscoDevNet/terraform-provider-fmc): FMC Terraform provider for policy configuration.
- [CiscoDevNet/terraform-provider-sccfm](https://github.com/CiscoDevNet/terraform-provider-sccfm): SCC/cdFMC Terraform provider for device lifecycle.
- [CiscoDevNet/FMCAnsible](https://github.com/CiscoDevNet/FMCAnsible): Ansible collection for FMC (`cisco.fmcansible`).
- [CiscoISE/ansible-ise](https://github.com/CiscoISE/ansible-ise): Ansible collection for ISE (`cisco.ise`).

---

## Constraints and known issues

- **ROPC + MFA incompatibility:** ISE REST ID uses ROPC, which cannot support MFA. RAVPN path is intentionally password-only. ZTAA path uses SAML + MFA. Two separate auth architectures by design.
- **cdFMC API parity:** Not explicitly confirmed to be 100% identical to on-prem FMC API. Verify at deploy time.
- **FTDv on Azure:** No transparent mode, no HA (active/standby), no jumbo frames, Gen 1 only. See `azure-demo-plan.md` for the full constraint list.
- **`[AppGroupName]` placeholder:** The ZTAA SAML Entity ID and ACS URL contain `[AppGroupName]`. Replace with the actual application group name when configuring the Entra Enterprise App and cdFMC SSO Server Object.
- **ISE Marketplace image version:** Check availability at deploy time. Plan name may be `cisco-ise_3_4` or `cisco-ise_3_5` depending on what Cisco has published.
- **FTDv Marketplace image version:** Target 10.x. Verify 10.0.x image availability at deploy time.

---

## Build order

Follow this sequence. Each step depends on the previous steps completing.

1. Build Terraform under `infra/`. Network first, then VMs.
2. Build the trading dashboard app (`app/`). Test locally with `npm run dev`.
3. Write deployment scripts (`scripts/`).
4. Write setup guides (`setup/`).
5. Configure pre-commit hooks and the `quality.yaml` GitHub Action.
6. End-to-end test against the Definition of done table.
7. Deferred (post-workshop): `automation/`, `docs/specs/`, `docs/` Jekyll site, dependabot, tfsec, frontend CI jobs.

### Verification checklist

Run these before declaring the build done. Each maps back to the Definition of done table.

- [ ] `terraform validate` and `terraform fmt -check -recursive` pass under `infra/`.
- [ ] `terraform apply` completes with no errors. All VMs reach `running` state.
- [ ] `pip-ftdv-outside` resolves correctly through `vpn.rooez.com` and `trading.rooez.com` Cloudflare A records.
- [ ] FTDv registers to cdFMC. The device appears in the cdFMC inventory as healthy.
- [ ] ISE web UI is reachable via Bastion tunnel. REST ID identity store test succeeds against Entra ID.
- [ ] Secure Client connects to `vpn.rooez.com` as `trader1@rooez.com`. The dark `/vpn` dashboard loads.
- [ ] Without the tunnel, `https://vpn.rooez.com/vpn` is unreachable.
- [ ] Browser to `https://trading.rooez.com/ztaa` redirects to Entra ID, prompts MFA, returns to the light `/ztaa` dashboard.
- [ ] cdFMC VPN dashboard shows the active RAVPN session with username, source IP, geographic location, and Secure Client version.
- [ ] Geo-based access control rule produces a visible difference for at least two source regions (test via VPN exit nodes or a second test client).
- [ ] `gitleaks` finds no secrets in the repo. `pre-commit run --all-files` is clean.

---

## Tear-down

Azure resources cost money while running. Tear down the environment when the workshop ends.

```bash
cd infra
terraform destroy
```

Confirm in the Azure portal that the resource group is gone. FTDv and ISE on Standard_D8s_v3/v4 are the dominant cost drivers; leaving them running for a week consumes the demo budget.

After `terraform destroy`:
- Remove the FTDv entry from cdFMC (Inventory > Devices > delete).
- Remove the FTDv as a NAD in ISE if ISE was preserved elsewhere.
- Remove Cloudflare A records for `vpn.rooez.com` and `trading.rooez.com`.
- Revoke the Let's Encrypt cert if not reusing it.
