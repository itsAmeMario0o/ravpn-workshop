# TLS certs

Let's Encrypt SAN cert covering both `vpn.rooez.com` and `trading.rooez.com`. DNS-01 challenge via Cloudflare.

## Prerequisites

- Cloudflare API token (see `dns-config.md`).
- DNS records already created (placeholder IP is fine).

## Run

Use staging first to confirm the chain works without burning rate-limit attempts:

```bash
export CF_API_TOKEN="..."
export EMAIL="dev@mariojruiz.com"

STAGING=1 scripts/generate-certs.sh
```

Inspect the staging cert. Once the chain is correct, run for real:

```bash
scripts/generate-certs.sh
```

Output: `./certs/config/live/ravpn-workshop/fullchain.pem` and `privkey.pem`.

## Verify

```bash
openssl x509 -in ./certs/config/live/ravpn-workshop/fullchain.pem -noout -text | grep DNS
```

Expected:

```
DNS:trading.rooez.com, DNS:vpn.rooez.com
```

```bash
openssl x509 -in ./certs/config/live/ravpn-workshop/fullchain.pem -noout -enddate
```

Expected: a date roughly 90 days out.

## Where the cert is used

- cdFMC binds it to the RAVPN connection profile (TLS to Secure Client).
- cdFMC binds it to the ZTAA Application Group (TLS to the user's browser).
- The trading app VM uses a separate self-signed cert for backend TLS only.

## Renewal

The cert lasts 90 days. For a workshop demo this is fine. Re-run `generate-certs.sh` if the demo runs longer than expected.

## Notes

- Rate limits: 5 duplicate certs per week per registered domain. Use `STAGING=1` while iterating.
- The `certs/` directory is gitignored.
