# TLS certs

ZTAA on FTD needs three different certs. They serve different purposes and come from different sources. Only one of them is what Let's Encrypt is for.

| Cert | What it does | Source | Where it goes |
|---|---|---|---|
| Identity cert | Presented by FTD to the user's browser when they hit any `*.rooez.com` host. The browser must trust the issuing CA. | Public CA. **Let's Encrypt wildcard SAN cert** covering `rooez.com` and `*.rooez.com`. | `Devices > Certificates > Add` in cdFMC, as PKCS12, with SSL Client + SSL Server flags. |
| SAML IdP cert | Validates SAML assertions coming back from Entra. | Embedded in the **Entra Federation Metadata XML** you download when configuring the Enterprise App. You don't generate it. | `Devices > Certificates > Manual enrollment > CA Only` in cdFMC. |
| Application cert | FTD uses this to terminate / inspect / re-encrypt the protected app's traffic. Requires the app server's own cert *and* private key. | **Self-signed**, generated locally by `scripts/generate-app-cert.sh`. The same pair is used by nginx on the app VM and uploaded to cdFMC. | `Objects > Object Management > PKI > Internal Certs > Add` in cdFMC, as both cert file and key file. |

The rest of this guide focuses on the identity cert (Let's Encrypt) and the application cert (self-signed). The IdP cert is handled in [entra-config.md](entra-config.md).

## How to think about these three certs

Each cert proves something different to a different audience. If you keep that in mind, the rest of the cert work is just plumbing.

**Identity cert** says: "I am `vpn.rooez.com` and `trading.rooez.com`."
- Audience: every browser and Secure Client that connects to FTD's outside interface.
- Trust requirement: must chain to a CA the audience already trusts. This is why we use Let's Encrypt — every browser and OS ships with the Let's Encrypt root in its trust store.
- Skip it and: every connection gets a TLS warning. Demo-able, but not what we want.

**SAML IdP cert** says: "this SAML assertion really came from Entra."
- Audience: just FTD, during the ZTAA login flow.
- Trust requirement: FTD needs Entra's public signing cert, so it can verify the signature on the SAML assertion. Entra signs with its private key, FTD verifies with the public key bundled in the metadata XML.
- Skip it and: anyone could forge a SAML assertion. Signing is what makes the SSO flow safe.

**Application cert** says: "I am the trading app server."
- Audience: just FTD, on the inside leg when it re-encrypts traffic to the app.
- Trust requirement: closed loop between FTD and one server inside the VNet. No public trust needed. Self-signed is fine because nobody outside this VNet ever sees it.
- Skip it and: FTD can't speak HTTPS to the app. ZTAA assumes the protected app is HTTPS.

Two-line mental model:
- **Outside-facing** (RAVPN clients, ZTAA browsers) → public CA → Let's Encrypt.
- **Inside-facing** (FTD trusting Entra, FTD reaching the app) → private trust → metadata-embedded cert + self-signed.

For the **RAVPN demo specifically**, only the identity cert is required. The SAML IdP cert and the application cert come into play during the ZTAA demo. We still generate all three up front because the wildcard Let's Encrypt cert covers both `vpn` and `trading` subdomains, and the app cert needs to be on the trading app VM before nginx starts.

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

Drop the `STAGING=1` and add `FORCE=1`:

```bash
FORCE=1 scripts/generate-certs.sh
```

`FORCE=1` adds `--force-renewal` to the certbot command. Without it, certbot sees the still-valid staging cert sitting at `certs/config/live/ravpn-demo/` and skips reissuance — its renewal logic doesn't notice that the existing cert was issued by the staging endpoint and the new request is for production. With force-renewal, certbot reissues regardless.

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

### Package the cert as PKCS12 for cdFMC

cdFMC's identity cert import expects a PKCS12 bundle, not loose PEM files. PKCS12 (`.p12`) is a single password-protected file that holds the cert, the issuing chain, and the private key together. Build it from the three Let's Encrypt outputs:

```bash
openssl pkcs12 -export \
  -inkey  certs/config/live/ravpn-demo/privkey.pem \
  -in     certs/config/live/ravpn-demo/cert.pem \
  -certfile certs/config/live/ravpn-demo/chain.pem \
  -name   ravpn-identity \
  -out    certs/config/live/ravpn-demo/ravpn-identity.p12
```

You'll be prompted for an export password. Pick a strong one and save it in your password manager — cdFMC asks for the same password when you import the bundle. Lose this password and you have to rebuild the `.p12`.

The `-name ravpn-identity` flag sets the friendly name embedded in the bundle. cdFMC shows that name in the cert list, so use something a future you will recognize.

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
