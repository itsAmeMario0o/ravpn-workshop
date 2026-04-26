# 24-hour execution plan

Phase-based plan for the RAVPN workshop build. Each phase has a goal, deliverables, validation gate, and recovery path.

Aligns with the build priority tiers, Definition of done table, and Verification checklist in `CLAUDE.md`. The detailed architecture lives in `azure-demo-plan.md`.

**Critical path constraints:** FTDv boot ~20 min, ISE first-boot ~45-60 min, Let's Encrypt DNS-01 ~5-15 min, marketplace term acceptance is a one-time gate. Build around these waits — do parallel work during boot windows.

---

## Phase 0 — Pre-flight (h-1 → h0, ~30 min)

**Goal:** No surprises blocking deploy.

- [ ] Confirm Azure subscription has Dsv3 (8 vCPU) and Dsv4 (8 vCPU) quota available in the chosen region.
- [ ] Run `az vm image terms accept` for both `cisco-ftdv` and `cisco-ise-virtual` plans.
- [ ] Confirm Cloudflare API token has DNS edit on `rooez.com`.
- [ ] Confirm SCC tenant has cdFMC provisioned. Copy the registration command + NAT ID.
- [ ] Install local toolchain: terraform, az cli, node 20, python 3.12, certbot, jq, pre-commit.

**Validation gate:**

- [ ] `az vm image show --publisher cisco --offer cisco-ftdv --plan ftdv-azure-byol` returns terms-accepted.
- [ ] `terraform version` >=1.6, `node --version` >=20.
- [ ] Marketplace terms confirmed in Azure portal.

**If fails:** stop. Quota requests can take hours.

---

## Phase 1 — External identity and DNS (h0 → h2.5)

**Goal:** Identity and DNS plumbing that infra will depend on.

Parallelizable in pairs:

1. Cloudflare A records: `vpn.rooez.com` and `trading.rooez.com` to placeholder `1.1.1.1`. DNS only (gray cloud).
2. Entra ID: add `rooez.com` custom domain, create `trader1@rooez.com`, register Microsoft Authenticator, create Enterprise App for ZTAA SAML, create App Registration for ISE REST ID with ROPC permissions.
3. Let's Encrypt SAN cert via certbot DNS-01 + Cloudflare plugin.

**Tests:**

- [ ] `dig vpn.rooez.com` and `dig trading.rooez.com` resolve from a public resolver.
- [ ] `openssl x509 -in fullchain.pem -text` shows both SANs.
- [ ] Sign in to Entra as `trader1@rooez.com` and complete MFA enrollment.

**Validation gate:**

- [ ] DNS resolves to placeholder.
- [ ] Cert covers both SANs, expiry > 60 days.
- [ ] `trader1` can sign in and MFA prompts work.
- [ ] App Registration client secret saved in a password manager.

**If fails:** identity is single-threaded — fix before infra phase.

---

## Phase 2 — Terraform infrastructure (h2.5 → h5)

**Goal:** All Azure resources declared, validated, ready to apply.

**Invoke skill:** `engineering-advanced-skills:terraform-patterns` at the start of this phase.

Build inside `infra/`:

1. `versions.tf` (provider pins).
2. `variables.tf` + `terraform.tfvars.example`.
3. `modules/network/` — VNet, six subnets, two NSGs (outside, AzureBastion).
4. `modules/bastion/` — Standard SKU + public IP.
5. `modules/ftdv/` — VM, four NICs, outside PIP, custom-data JSON.
6. `modules/ise/` — VM, identity NIC, user-data plaintext.
7. `modules/app/` — Ubuntu B1s, inside NIC, cloud-init that installs nginx.
8. `main.tf` — wire the modules.
9. `outputs.tf` — surface FTDv outside PIP, Bastion FQDN, ISE private IP, app private IP.

**Tests (continuous during this phase):**

- [ ] `terraform fmt -check -recursive` clean.
- [ ] `terraform init -backend=false` resolves providers.
- [ ] `terraform validate` clean.
- [ ] `tfsec .` no high or critical findings.

**Validation gate:**

- [ ] `terraform plan` runs clean, ~25-35 resources expected.
- [ ] `tfsec` clean at high/critical.
- [ ] Variables have descriptions and types; sensitive ones marked.

**If fails:** simplify. If you are nesting `for_each` over `for_each`, stop and inline.

---

## Phase 3 — Apply and boot wait (h5 → h6)

**Goal:** Resources created, VMs booted enough to interact with.

- [ ] `terraform apply -auto-approve`.
- [ ] Update Cloudflare A records from placeholder to the real `pip-ftdv-outside`.
- [ ] During boot wait: build the React app locally (`npm run build`), test both routes with `npm run dev`.

**Tests during boot wait:**

- [ ] `npx tsc --noEmit` clean.
- [ ] `npx eslint src/ --max-warnings 0` clean.
- [ ] `npx vitest run` passes (at least one smoke test per route).
- [ ] Manual: `localhost:5173/vpn` and `localhost:5173/ztaa` render correct themes.

**Validation gate:**

- [ ] All Terraform resources reach `Succeeded` / `Running`.
- [ ] DNS propagation: `dig vpn.rooez.com` returns the FTDv outside PIP.
- [ ] App builds clean, both routes render.

**If fails:** for boot timeouts, give it 30 min before declaring failure (FTDv 10.x first-boot is slow).

---

## Phase 4 — Initial integration (h6 → h8)

**Goal:** FTDv talks to cdFMC, app deployed, base connectivity verified.

Sequential:

1. SSH to FTDv via Bastion. Configure data-interface management: `configure network management-data-interface`. Then `configure manager add <SCC FQDN> <regkey> <natid>`.
2. Watch cdFMC inventory; FTDv should reach "registered" within 5-10 min.
3. SCP the React build + nginx config to the app VM. Run `scripts/deploy-trading-app.sh`.
4. From an inside test, curl `https://<app private IP>/vpn` and `/ztaa` — confirm 200 and correct themes.

**Tests:**

- [ ] cdFMC: device health green.
- [ ] App VM: `systemctl status nginx` active, cert correctly bound.
- [ ] Network: FTDv inside interface can reach app on 443.

**Validation gate:**

- [ ] FTDv registered to cdFMC, no policy yet.
- [ ] App reachable from inside, both routes serve correct themes.
- [ ] Cert valid, no SAN/CN mismatch.

**If fails:** most common breakage point. Top causes: outbound 443 blocked from FTDv, Day-0 JSON malformed, regkey/NAT ID typo, sftunnel sourced from wrong interface.

---

## Phase 5 — Policy configuration (h8 → h13)

**Goal:** All four live demos working end to end.

### 5a. Base FTD policy (h8 → h9)

Access control policy, NAT for outside, route to inside subnet for app reachability. Skip if not needed for demo.

### 5b. ISE config (h9 → h10.5)

- [ ] REST ID identity source pointing at App Registration in Entra (ROPC).
- [ ] Add FTDv as NAD with shared secret.
- [ ] Auth policy: RADIUS request from FTDv to REST ID.
- [ ] Authz policy: matched users to permit.
- [ ] Test from ISE Live Logs: dummy RADIUS test against `trader1@rooez.com` succeeds.

### 5c. RAVPN connection profile on cdFMC (h10.5 → h11.5)

- [ ] AAA: RADIUS server group to ISE.
- [ ] Connection profile `ravpn-default`, group alias visible.
- [ ] Address pool, split tunnel as desired.
- [ ] Cert: bind the Let's Encrypt cert.

### 5d. Geolocation profiles (h11.5 → h12)

- [ ] Second connection profile.
- [ ] Geo-based access control rules tied to country objects.

### 5e. ZTAA (h12 → h13)

- [ ] SSO Server Object pointing at Entra Enterprise App. Replace `[AppGroupName]` placeholder with real value.
- [ ] Application Group with `trading.rooez.com/ztaa` as protected app, FTDv as enforcement point.
- [ ] Bind cert.

**Tests (per sub-phase, smallest unit first):**

- [ ] 5b: ISE RADIUS test from CLI.
- [ ] 5c: connect Secure Client from your laptop, confirm tunnel up, confirm `vpn.rooez.com/vpn` loads dark theme.
- [ ] 5d: connect from a second IP (mobile hotspot or VPN exit node) and confirm geo policy hits a different rule.
- [ ] 5e: incognito browser to `https://trading.rooez.com/ztaa` redirects to Entra, prompts MFA, returns to `/ztaa` light theme.

**Validation gate (every Definition of done row):**

- [ ] RAVPN: Secure Client login lands on `/vpn`, `/vpn` unreachable without tunnel.
- [ ] Geo: two source regions hit different policy outcomes.
- [ ] ZTAA: SAML+MFA flow returns `/ztaa`.
- [ ] cdFMC dashboard: active session shows username, source IP, geo, client version.

**If fails:** isolate the layer. RAVPN broken? Test FTDv to ISE RADIUS independently of ISE to Entra ROPC. ZTAA broken? Test FTDv to Entra SAML in isolation before adding the app group.

---

## Phase 6 — End-to-end validation (h13 → h15)

**Goal:** Run the full Verification checklist from `CLAUDE.md` from a clean state.

- [ ] Disconnect VPN, close browser, clear cookies.
- [ ] Walk every checkbox in the verification table.
- [ ] Run the demo script you will use in front of the audience at least once, top to bottom.
- [ ] Time each demo block — flag any that exceed the workshop's per-section budget.

**Validation gate:**

- [ ] Every box in the Verification checklist passes from a cold-start client.
- [ ] One full dry-run completed without consulting setup guides.

**If fails:** for any flaky demo, write a recovery one-liner. Add it to the relevant setup guide.

---

## Phase 7 — Tier-2: pre-commit and CI (h15 → h17)

**Goal:** Pre-commit hooks and CI green.

**Invoke skill:** `engineering-advanced-skills:ci-cd-pipeline-builder`.

- [ ] `.gitignore` per CLAUDE.md spec.
- [ ] `.gitleaks.toml` per CLAUDE.md spec.
- [ ] `.pre-commit-config.yaml` with gitleaks + terraform_fmt only (defer tfsec to tier-3 if it slows you down).
- [ ] `.github/workflows/quality.yaml` with terraform fmt/validate + gitleaks job. Defer tfsec, frontend, python jobs.
- [ ] Run `pre-commit run --all-files` locally — everything green.
- [ ] Push branch, watch CI green.

**Tests:**

- [ ] `pre-commit run --all-files` exits 0.
- [ ] GitHub Actions run shows green for terraform + gitleaks jobs.

**Validation gate:**

- [ ] No secret in repo (`gitleaks detect` clean).
- [ ] CI green on the branch.

**If fails:** disable failing hooks (do not `--no-verify`). If pre-commit blocks the build, drop to tier-3.

---

## Phase 8 — Setup guides (h17 → h22)

**Goal:** Someone else could rebuild this from `setup/` alone.

**Invoke skill:** `humanizer` on each file before committing.

Write incrementally, in this order:

1. [ ] `prerequisites.md`
2. [ ] `azure-setup.md`
3. [ ] `dns-config.md`
4. [ ] `tls-certs.md`
5. [ ] `entra-config.md`
6. [ ] `cdFMC-registration.md`
7. [ ] `ise-config.md`
8. [ ] `setup/README.md` (sequence + verification per step)

**Tests:**

- [ ] Read each guide top to bottom. Anywhere you skip steps from memory is a doc gap — fix.
- [ ] Pre-commit catches trailing whitespace, missing EOF newlines.

**Validation gate:**

- [ ] Every setup file has a "Verify" subsection that names a concrete check (curl, dig, az command, ISE Live Log entry).
- [ ] Every "Verify" check is one a fresh user could run.

**If fails:** if running long, drop `cdFMC-registration.md` and `ise-config.md` to bullet lists with screenshots — the workshop is live-driven anyway.

---

## Phase 9 — Final rehearsal (h22 → h24)

**Goal:** No surprises at workshop time.

- [ ] Tear-down dry run: `terraform destroy -auto-approve` on a throwaway clone, confirm clean. Do **not** destroy production demo.
- [ ] Re-deploy from scratch using only `setup/README.md`. Time it.
- [ ] Capture a screen recording of one full demo flow (RAVPN to ZTAA to dashboard). Fallback if live demo gods are unkind.
- [ ] Commit + push everything. Tag `v1.0-workshop`.

**Validation gate:**

- [ ] Cold redeploy from `setup/` works in under 90 minutes.
- [ ] Screen recording captures all four live demos cleanly.
- [ ] Repo tagged.

**If fails:** if cold redeploy does not fit in 90 min, that is a tomorrow problem — stop, sleep, rely on the running environment.

---

## Risk register (top 5)

| Risk | Likelihood | Mitigation |
|---|---|---|
| ROPC + App Registration permissions wrong, ISE auth fails | High | Test ISE to Entra ROPC in isolation early (phase 5b first thing). |
| FTDv sftunnel cannot reach SCC | Medium | Phase 4 validates this. Check `nsg-outside` allows TCP 8305 outbound and `configure network management-data-interface` was run. |
| Let's Encrypt rate limit hit | Low | Use `--staging` while iterating. Switch to prod when chain is correct. |
| ZTAA `[AppGroupName]` placeholder left unresolved | Medium | Grep both Entra Enterprise App Entity ID and cdFMC SSO Server Object for the literal `[AppGroupName]` before testing. |
| Cloudflare orange cloud (proxied) breaks RAVPN | Medium | Visual check: gray cloud = DNS only. Document in `dns-config.md`. |

---

## Parallelization summary

Use boot windows for unrelated work:

- During FTDv boot (~20 min after `terraform apply`): build the React app, run typecheck/lint/vitest.
- During ISE first-boot (~45-60 min): write base FTD ACP, draft setup guides for completed phases, configure Cloudflare A records to real PIP.
- During Phase 5b ISE policy work: have phase 5e ZTAA Entra Enterprise App pre-staged in another tab.

---

## Out of scope

Per the tier-3 list in `CLAUDE.md`:

- `docs/` Jekyll site
- `docs/specs/` formal specs
- `automation/` Python and PowerShell wrappers
- tfsec, dependabot, frontend CI jobs

These can ship post-workshop without affecting any of the four demos.
