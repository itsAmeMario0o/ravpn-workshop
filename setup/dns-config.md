# DNS config

Two hostnames point at the firewall: `vpn.rooez.com` is what the VPN client connects to, and `trading.rooez.com` is what the browser hits for the zero-trust path. Both resolve to the same public IP — the FTDv outside interface — and the firewall serves a different connection profile based on which name the client used.

## The one setting that breaks everything

In Cloudflare, the cloud icon next to each A record must be **gray (DNS only)**. If it is orange (proxied), Cloudflare terminates the connection itself, and:

- The Secure Client tunnel never reaches the firewall.
- The ZTAA SAML callback breaks because Cloudflare strips the cert.

Click the cloud icon until it turns gray. Confirm before every test.

## Initial records

Before you run `terraform apply`, you do not yet know the firewall's public IP. Create both records pointed at a placeholder so DNS exists:

| Type | Name | Content | Proxy |
|---|---|---|---|
| A | vpn | 1.1.1.1 | DNS only |
| A | trading | 1.1.1.1 | DNS only |

Update both records to the real IP after `terraform apply` finishes.

## Cloudflare API token

To run the cert generation script, you need a Cloudflare API token with permission to edit DNS for `rooez.com`.

In the Cloudflare dashboard: **My Profile > API Tokens > Create Token > Custom token**. Permissions:

- Zone > DNS > Edit on `rooez.com`

Save the token in your password manager and as an environment variable named `CF_API_TOKEN`. The cert script reads it from there.

## Update with the real IP

After Terraform deploys, the firewall's public IP comes out as a Terraform output. Read it and update both A records:

```bash
cd infra
TARGET_IP=$(terraform output -raw ftdv_outside_public_ip)
echo "$TARGET_IP"
```

You can update via the Cloudflare UI or via API. The API version, replacing both records:

```bash
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

Both must return the FTDv outside IP, not `1.1.1.1`. Cloudflare propagates fast, usually under a minute. If `dig` returns no answer, check the cloud icon — proxied records sometimes hide the IP entirely.
