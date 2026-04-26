# Setup walkthrough

This is the build guide. Read it top to bottom the first time. Once the environment is up, you can dip into individual files when something needs fixing.

The end state: a single Azure region running an FTDv firewall, an ISE node, an Azure Bastion, and an Ubuntu VM hosting a small trading dashboard. A user signs in through Cisco Secure Client and lands on the dashboard. A second user opens a browser, hits the same dashboard through the firewall acting as a zero-trust broker, and signs in with Entra ID and MFA. Both work. That is the workshop.

You do not need to be an expert in any of these products. You do need an Azure subscription, a Cloudflare account managing one domain, a Cisco Smart Account, and a Security Cloud Control tenant with cdFMC already provisioned. The first guide lists everything in detail.

## Sequence

Follow these in order. Each one ends with a Verify subsection. Do not skip to the next step until Verify passes.

1. [Prerequisites](prerequisites.md) - tools and accounts.
2. [Azure setup](azure-setup.md) - subscription, region, marketplace terms.
3. [DNS config](dns-config.md) - Cloudflare A records.
4. [TLS certs](tls-certs.md) - generate two certs locally: the Let's Encrypt identity cert (Cisco Secure Client and the browser see this) and the self-signed application cert (the firewall and the app's nginx use this for backend TLS). Run `scripts/generate-certs.sh` and `scripts/generate-app-cert.sh`.
5. [Entra ID](entra-config.md) - demo user, MFA, Enterprise App (for ZTAA SAML), App Registration (for ISE REST ID). Also where you download the SAML IdP cert as part of the Federation Metadata XML.
6. Terraform deploy - copy `infra/terraform.tfvars.example` to `infra/terraform.tfvars`, fill the values, then run `terraform init && terraform plan && terraform apply` from inside `infra/`.
7. [cdFMC registration](cdFMC-registration.md) - SSH to FTDv through Bastion and register the device with cdFMC. After registration, upload all three certs to cdFMC: identity cert (Devices > Certificates, PKCS12), SAML IdP cert (Devices > Certificates, Manual + CA Only), application cert (Objects > PKI > Internal Certs).
8. [ISE config](ise-config.md) - REST ID identity store, FTDv as a network access device, auth and authz policies.
9. Trading app deploy - run `scripts/deploy-trading-app.sh` to build the React app and push it (along with the local application cert) to the VM.

## Things that will trip you up

- **Two identity flows, on purpose.** RAVPN uses ROPC, which means the username and password go to Entra without MFA. ZTAA uses SAML and adds MFA. This is intentional. Mixing them up is the most common mistake.
- **FTDv management has no public IP.** Bastion is the only admin path. cdFMC registration sftunnel comes out the data interface, not the management interface. You will run `configure network management-data-interface` on the FTD CLI before the registration command will succeed.
- **Cloudflare must stay gray.** The cloud icon next to your A record turns orange when the record is proxied. Proxied breaks both the RAVPN tunnel and the ZTAA SAML callback. Click it back to gray (DNS only).
- **The `[AppGroupName]` placeholder.** ZTAA uses SAML between Entra and cdFMC. The Entity ID and ACS URL contain the literal string `[AppGroupName]`. Replace that string with the same value in both Entra and cdFMC before you test.
- **Three certs, three sources, three upload paths.** ZTAA needs an identity cert (Let's Encrypt, public CA), a SAML IdP cert (downloaded from Entra inside the Federation Metadata XML), and an application cert (self-signed, generated locally). Each lands in a different cdFMC location. See `tls-certs.md` for the table.

## Optional add-ons

- [Extending ZTAA to additional applications](ztaa-extensions.md) - the same zero-trust pattern works for ISE's admin GUI and any other internal HTTPS app. Includes the generic flow and a worked example for ISE.

## Tear-down

When the workshop ends, take the environment down. The FTDv and ISE VMs are the cost drivers; leaving them running is expensive.

```bash
cd infra
terraform destroy
```

After destroy completes, remove the FTDv from the cdFMC inventory, drop the Cloudflare A records for `vpn.rooez.com` and `trading.rooez.com`, and revoke the Let's Encrypt cert if you do not plan to reuse it.
