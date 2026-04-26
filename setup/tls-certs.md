# TLS certs

ZTAA on FTD needs three different certs. They serve different purposes and come from different sources. Only one of them is what Let's Encrypt is for.

| Cert | What it does | Source | Where it goes |
|---|---|---|---|
| Identity cert | Presented by FTD to the user's browser when they hit any `*.rooez.com` host. The browser must trust the issuing CA. | Public CA. **Let's Encrypt wildcard SAN cert** covering `rooez.com` and `*.rooez.com`. | `Devices > Certificates > Add` in cdFMC, as PKCS12, with SSL Client + SSL Server flags. |
| SAML IdP cert | Validates SAML assertions coming back from Entra. | Embedded in the **Entra Federation Metadata XML** you download when configuring the Enterprise App. You don't generate it. | `Devices > Certificates > Manual enrollment > CA Only` in cdFMC. |
| Application cert | FTD uses this to terminate / inspect / re-encrypt the protected app's traffic. Requires the app server's own cert *and* private key. | **Self-signed**, generated locally by `scripts/generate-app-cert.sh`. The same pair is used by nginx on the app VM and uploaded to cdFMC. | `Objects > Object Management > PKI > Internal Certs > Add` in cdFMC, as both cert file and key file. |

The rest of this guide focuses on the identity cert (Let's Encrypt) and the application cert (self-signed). The IdP cert is handled in [entra-config.md](entra-config.md).

## Identity cert: Let's Encrypt

We use a Let's Encrypt wildcard SAN cert covering `rooez.com` and `*.rooez.com`. One cert covers every subdomain you might add later (`vpn`, `trading`, `ise`, anything else), so you do not have to re-issue when you ZTAA-enable a new app. Let's Encrypt verifies that you control the domain through a DNS-01 challenge: they ask for a specific TXT record, certbot adds it via the Cloudflare API, Let's Encrypt sees it, and issues the cert. You do not need a public IP or a web server for this. The validation is entirely DNS-based.

### Before you run

- A Cloudflare API token with DNS edit on `rooez.com`. See [dns-config.md](dns-config.md).
- Both A records already created (the placeholder IP from the DNS step is fine).
- certbot installed locally (`brew install certbot`).

### A note on the EMAIL variable

The `EMAIL` env var the script asks for is the **Let's Encrypt ACME account email**. Let's Encrypt uses it to send cert-expiration warnings and as the recovery contact for your ACME account. **It does not need to be at the domain you're getting the cert for.** Any inbox you control works. If your registered domain has no mailbox set up, use a personal or work address you actually read.

### Use staging first

Let's Encrypt rate-limits production cert issuance to 5 per week per registered domain. While you are confirming the chain works, use the staging endpoint. It has much higher limits but produces a cert your browser will not trust.

```bash
export CF_API_TOKEN="..."
export EMAIL="<your-email>"

STAGING=1 scripts/generate-certs.sh
```

Look at the output. If you see a fullchain.pem and privkey.pem under `./certs/config/live/ravpn-demo/`, the chain is working.

### Now generate the real cert

Drop the `STAGING=1` and run again:

```bash
scripts/generate-certs.sh
```

This produces the real cert, valid for 90 days, signed by a CA your browser trusts.

### Verify

Look at the SANs:

```bash
openssl x509 -in ./certs/config/live/ravpn-demo/fullchain.pem -noout -text | grep DNS
```

Expected:

```
DNS:*.rooez.com, DNS:rooez.com
```

The wildcard `*.rooez.com` covers any single-level subdomain. The bare `rooez.com` is a separate SAN because wildcards do not match the apex.

Look at the expiry:

```bash
openssl x509 -in ./certs/config/live/ravpn-demo/fullchain.pem -noout -enddate
```

Expected: a date roughly 90 days from now.

### Renewal and rate limits

The Let's Encrypt cert lasts 90 days. For a one-day workshop this is fine. If the demo runs longer than expected, re-run `generate-certs.sh` to renew. Production-tier issuance is rate-limited to 5 per week per registered domain — that's why we always validate against staging first.

## Application cert: self-signed

The application cert is the one FTD uses to terminate and re-encrypt traffic to the trading app behind the firewall. We generate it locally so the same cert + key can be uploaded to cdFMC and pushed to the app VM in one motion.

```bash
scripts/generate-app-cert.sh
```

Output:

- `certs/app/trading.crt` — the cert
- `certs/app/trading.key` — the private key

The script uses a CN of `trading-internal` and an 825-day validity. Both files are gitignored — the `certs/` directory is excluded from the repo so private keys never leave your laptop.

### Verify

```bash
openssl x509 -in certs/app/trading.crt -noout -subject -dates
```

Expected: `subject=CN = trading-internal` and a date 825 days out.

### Where each cert goes

| Cert | cdFMC location | Other use |
|---|---|---|
| Identity (Let's Encrypt) | `Devices > Certificates`, PKCS12, SSL Client + SSL Server | Bound to the RAVPN connection profile and the ZTAA application group. |
| SAML IdP (from Entra) | `Devices > Certificates`, Manual enrollment, CA Only | Bound to the SAML SSO server object for the ZTAA application group. |
| Application (self-signed) | `Objects > Object Management > PKI > Internal Certs > Add` (upload both `.crt` and `.key`) | Pushed to the app VM by `scripts/deploy-trading-app.sh` so nginx serves it. |
