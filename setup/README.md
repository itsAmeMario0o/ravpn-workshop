# Setup walkthrough

Build the JPMC RAVPN demo from scratch. Each step has a verify subsection. If verify fails, fix before moving on.

## Sequence

1. [Prerequisites](prerequisites.md) - tools and accounts.
2. [Azure setup](azure-setup.md) - subscription, region, marketplace terms.
3. [DNS config](dns-config.md) - Cloudflare A records.
4. [TLS certs](tls-certs.md) - Let's Encrypt SAN cert.
5. [Entra ID](entra-config.md) - demo user, MFA, Enterprise App, App Registration.
6. Terraform deploy - copy `infra/terraform.tfvars.example` to `infra/terraform.tfvars`, fill values, run `terraform init && terraform plan && terraform apply` from `infra/`.
7. [cdFMC registration](cdFMC-registration.md) - SSH FTDv via Bastion, configure data-interface management, paste `configure manager add`.
8. [ISE config](ise-config.md) - REST ID, NAD, auth and authz policies.
9. Trading app deploy - `scripts/deploy-trading-app.sh`.

## Notes

- Identity flows: RAVPN uses ROPC (no MFA), ZTAA uses SAML+MFA. Two intentional architectures.
- Management plane: FTDv mgmt has no public IP. cdFMC sftunnel sources from the data interface.
- Cloudflare: gray cloud (DNS only), never orange (proxied).
- ZTAA: replace the literal `[AppGroupName]` placeholder in both the Entra Enterprise App and the cdFMC SSO Server Object with the same string before testing.

## Tear-down

```bash
cd infra
terraform destroy
```

Then remove the FTDv from cdFMC, drop Cloudflare A records, and revoke the cert if not reusing.
