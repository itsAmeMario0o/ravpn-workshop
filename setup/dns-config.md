# DNS config

Cloudflare A records for `vpn.rooez.com` and `trading.rooez.com`. Both point at the FTDv outside public IP.

## Critical setting

**DNS only (gray cloud), never proxied (orange cloud).** Cloudflare proxy breaks RAVPN tunnel negotiation and ZTAA SAML callbacks. If the cloud icon is orange, click it until it turns gray.

## Initial records

Before `terraform apply`, point both records at a placeholder:

| Type | Name | Content | Proxy |
|---|---|---|---|
| A | vpn | 1.1.1.1 | DNS only |
| A | trading | 1.1.1.1 | DNS only |

Update to the real IP after `terraform apply` produces `ftdv_outside_public_ip`.

## API token

Create a Cloudflare API token with permissions:

- Zone > DNS > Edit on `rooez.com`

Save as `CF_API_TOKEN` in your shell or password manager. Required for `scripts/generate-certs.sh`.

## Update with the real IP

```bash
cd infra
TARGET_IP=$(terraform output -raw ftdv_outside_public_ip)

# Replace via Cloudflare API or UI. Example via curl:
curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$VPN_RECORD_ID" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"name\":\"vpn\",\"content\":\"$TARGET_IP\",\"proxied\":false}"
```

## Verify

```bash
dig +short vpn.rooez.com @1.1.1.1
dig +short trading.rooez.com @1.1.1.1
```

Both must return the FTDv outside IP, not the placeholder.

## Notes

- Propagation is fast for Cloudflare (under 1 minute).
- If `dig` shows no answer, the record may still be proxied. Check the dashboard.
