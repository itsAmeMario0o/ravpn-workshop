# Setup walkthrough

This is the build guide. Read it top to bottom the first time. Once the environment is up, you can dip into individual files when something needs fixing.

The end state: a single Azure region running an FTDv firewall, an ISE node, an Azure Bastion, and an Ubuntu VM hosting a small trading dashboard. A user signs in through Cisco Secure Client and lands on the dashboard. A second user opens a browser, hits the same dashboard through the firewall acting as a zero-trust broker, and signs in with Entra ID and MFA. Both work. That is the workshop.

You do not need to be an expert in any of these products. You do need an Azure subscription, a Cloudflare account managing one domain, a Cisco Smart Account, and a Security Cloud Control tenant with cdFMC already provisioned. The first guide lists everything in detail.

## Sequence

Follow these in order. Each one ends with a Verify subsection. Do not skip to the next step until Verify passes.

### Phase 1 — Local config (nothing in Azure yet)

1. [Prerequisites](prerequisites.md) - tools and accounts.
2. [Azure setup](azure-setup.md) - subscription, region, marketplace terms.
3. [DNS config](dns-config.md) - Cloudflare A records (placeholder IP for now).
4. [TLS certs](tls-certs.md) - generate two certs locally: the Let's Encrypt identity cert and the self-signed application cert.
5. [Entra ID](entra-config.md) - demo user, MFA, Enterprise App, App Registration.
6. [SCC pre-provisioning](scc-onboarding.md) - create the pending FTDv record, claim licenses, save the reg key, NAT ID, and full `configure manager add` command.

### Phase 2 — Provision the platform (Azure resources come up)

7. [Terraform deploy](terraform-deploy.md) - VNet, subnets, FTDv, trading app, Bastion. Update Cloudflare A records with the real FTDv outside IP after apply finishes. Note: ISE is **not** deployed by Terraform — the ISE module is commented out because the Cisco ISE Marketplace image fails Terraform's create path with `OSProvisioningTimedOut`. See `LESSONS-LEARNED.md`.
8. [ISE Portal deploy](ise-portal-deploy.md) - click-through deploy of ISE through the Azure Portal. Takes 10 minutes of clicks plus 45-60 minutes of first-boot wait. Verify with `show application status ise` over Bastion.

### Phase 3 — Configure the security stack (the parts that depend on each other)

9. [cdFMC registration](cdFMC-registration.md) - SSH to FTDv through Bastion, run `configure network management-data-interface`, then paste the `configure manager add ...` command from step 6. Wait for FTDv to appear as healthy in cdFMC inventory.
10. [ISE config](ise-config.md) - in the ISE GUI: enable REST Auth Service, create the REST ID identity source pointing at Entra, add the FTDv as a Network Access Device (write down the RADIUS shared secret), build the policy set. Skip the FTDv-side Verify step at the end of this guide for now — it depends on cdFMC RAVPN config that comes after step 11.
11. Upload certs to cdFMC - identity cert (Devices > Certificates as PKCS12), SAML IdP cert (Devices > Certificates, Manual + CA Only), application cert (Objects > PKI > Internal Certs). Reference table in `tls-certs.md`.

### Phase 4 — RAVPN end-to-end

12. cdFMC RAVPN configuration - AAA server group pointing at ISE (10.100.4.10) using the shared secret from step 10, RAVPN connection profile, address pool, group policy, IPv4 access list, identity cert binding, deploy.
13. Trading app deploy - run `scripts/deploy-trading-app.sh` to build the React app and push it (along with the local application cert) to the VM. Both the `/vpn` and `/ztaa` routes need to be live before any end-to-end test.
14. Verify RAVPN - back to the ISE-config Verify step (`test aaa-server` from FTDv CLI through Bastion). Then from a laptop with Cisco Secure Client, connect to `vpn.rooez.com` as `trader1@rooez.com`. The dark `/vpn` dashboard loads.

### Phase 5 — ZTAA end-to-end

15. cdFMC ZTAA configuration - SAML IdP setup, Application Group with identity + application certs, per-app policy, deploy.
16. Verify ZTAA - browser to `https://trading.rooez.com/ztaa`, redirected to Entra ID, prompt for MFA, return to the light `/ztaa` dashboard.

### Phase 6 — Sign-off

17. cdFMC dashboard check - the active RAVPN session is visible with username, source IP, geographic location, Secure Client version.
18. Run `scripts/smoke-test.sh` - all green except the items that intentionally cannot be programmatically verified (Secure Client connect, ZTAA redirect).

## Things that will trip you up

- **Two identity flows, on purpose.** RAVPN uses ROPC, which means the username and password go to Entra without MFA. ZTAA uses SAML and adds MFA. This is intentional. Mixing them up is the most common mistake.
- **FTDv management has no public IP.** Bastion is the only admin path. cdFMC registration sftunnel comes out the data interface, not the management interface. You will run `configure network management-data-interface` on the FTD CLI before the registration command will succeed.
- **Cloudflare must stay gray.** The cloud icon next to your A record turns orange when the record is proxied. Proxied breaks both the RAVPN tunnel and the ZTAA SAML callback. Click it back to gray (DNS only).
- **The `[AppGroupName]` placeholder.** ZTAA uses SAML between Entra and cdFMC. The Entity ID and ACS URL contain the literal string `[AppGroupName]`. Replace that string with the same value in both Entra and cdFMC before you test.
- **Three certs, three sources, three upload paths.** ZTAA needs an identity cert (Let's Encrypt, public CA), a SAML IdP cert (downloaded from Entra inside the Federation Metadata XML), and an application cert (self-signed, generated locally). Each lands in a different cdFMC location. See `tls-certs.md` for the table.

## Reference

- [Bastion access](bastion-access.md) - how to reach FTDv, ISE, and the trading app through Azure Bastion. Read this before step 9 if you have not used Bastion before.

## Optional add-ons

- [Extending ZTAA to additional applications](ztaa-extensions.md) - the same zero-trust pattern works for ISE's admin GUI and any other internal HTTPS app. Includes the generic flow and a worked example for ISE.

## Tear-down

When the workshop ends, take the environment down. The FTDv and ISE VMs are the cost drivers; leaving them running is expensive.

The ISE VM was deployed via the Portal, so Terraform does not know about it. Delete it explicitly first:

```bash
az vm delete -g rg-ravpn-demo -n vm-ise --yes
az disk list -g rg-ravpn-demo --query "[?starts_with(name, 'vm-ise_OsDisk')].name" -o tsv | xargs -I{} az disk delete -g rg-ravpn-demo -n {} --yes
az network nic list -g rg-ravpn-demo --query "[?contains(name, 'vm-ise')].name" -o tsv | xargs -I{} az network nic delete -g rg-ravpn-demo --name {}
```

Then destroy the rest with Terraform:

```bash
cd infra
terraform destroy
```

After destroy completes, remove the FTDv from the cdFMC inventory, drop the Cloudflare A records for `vpn.rooez.com` and `trading.rooez.com`, and revoke the Let's Encrypt cert if you do not plan to reuse it.
