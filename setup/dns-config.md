# DNS config

Three hostnames point at the firewall:

- `vpn.rooez.com` — what Cisco Secure Client connects to for the RAVPN demo.
- `trading.rooez.com` — what the browser hits for the ZTAA demo.
- `ise.rooez.com` — what the browser hits for the optional ZTAA-protected ISE GUI (see `ztaa-extensions.md`). Skip this one if you are not adding the ISE add-on.

All three resolve to the same public IP (the FTDv outside interface), and the firewall serves a different application or connection profile based on which name the client used.

## The one setting that breaks everything

In Cloudflare, the cloud icon next to each A record must be **gray (DNS only)**. If it is orange (proxied), Cloudflare terminates the connection itself, and:

- The Secure Client tunnel never reaches the firewall.
- The ZTAA SAML callback breaks because Cloudflare strips the cert.

Click the cloud icon until it turns gray. Confirm before every test.

## Step 1 — Confirm the domain is in Cloudflare

Sign in at `https://dash.cloudflare.com`. The home screen shows your zones (domains). Click into `rooez.com`.

On the right side of the zone overview, the **API** card shows the **Zone ID** — a 32-character hex string. Copy it somewhere safe; you do not need it for the next steps but it is useful for direct API debugging later.

## Step 2 — Create an API token

The token is what `scripts/generate-certs.sh` uses to add the DNS-01 challenge TXT record during cert issuance. It only needs DNS-edit permission on this one zone.

1. Top-right corner of the dashboard → click your profile icon → **My Profile**.
2. Left sidebar → **API Tokens**.
3. Click **Create Token**.
4. Ignore the templates. Scroll down and click **Create Custom Token**.
5. Token name: anything you will recognize, like `ravpn-demo-dns`.
6. **Permissions** — set one row:
   - First dropdown: `Zone`
   - Second dropdown: `DNS`
   - Third dropdown: `Edit`
7. **Zone Resources** — set one row:
   - First dropdown: `Include`
   - Second dropdown: `Specific zone`
   - Third dropdown: `rooez.com`
8. Leave **Client IP Address Filtering** blank and **TTL** as default.
9. Click **Continue to summary**, then **Create Token**.
10. Cloudflare shows the token **once**. Copy it now. There is no way to retrieve it later.

## Step 3 — Save the token to your shell

In a terminal:

```bash
export CF_API_TOKEN="<paste-the-token-here>"
export EMAIL="<your-email>"
```

The `EMAIL` is the Let's Encrypt ACME account contact. Any inbox you control is fine — it does not need to be at `rooez.com`.

These vars live only in this terminal session. If you want them to persist, drop both lines into a local `.envrc` file (the repo's `.gitignore` covers `.env*`, so it stays local) and source it in new shells.

### Verify the token works

```bash
curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json"
```

Expected: a JSON response containing `"status": "active"`. Anything else means the token is wrong — go back to step 2.

## Step 4 — Create the A records

Cloudflare dashboard for `rooez.com` → left sidebar → **DNS** → **Records**.

Create three records with the same settings except for the Name field. Set placeholder IPs now; you update them to the real FTDv outside IP after `terraform apply`.

| Type | Name | Content | Proxy |
|---|---|---|---|
| A | `vpn` | `1.1.1.1` | DNS only (gray cloud) |
| A | `trading` | `1.1.1.1` | DNS only (gray cloud) |
| A | `ise` | `1.1.1.1` | DNS only (gray cloud) |

For each one:

1. Click **Add record**.
2. **Type**: `A`.
3. **Name**: just the subdomain (`vpn`, `trading`, or `ise`). Cloudflare auto-appends `.rooez.com`.
4. **IPv4 address**: `1.1.1.1`.
5. **Proxy status**: confirm the cloud icon is **gray**. If it is orange, click it.
6. **TTL**: Auto.
7. Click **Save**.

After all three are saved, the records page should list them with the gray cloud icon next to each.

## Step 5 — Verify with dig

Use either form. The first uses your laptop's default resolver; the second asks Cloudflare's resolver directly, which sidesteps any local cache issue.

```bash
for r in vpn trading ise; do
  printf "%-20s %s\n" "${r}.rooez.com" "$(dig +short ${r}.rooez.com)"
done
```

```bash
for r in vpn trading ise; do
  printf "%-20s %s\n" "${r}.rooez.com" "$(dig +short ${r}.rooez.com @1.1.1.1)"
done
```

Each line should show `1.1.1.1` (yes, the placeholder happens to share the IP of Cloudflare's resolver — coincidence, not a problem). Cloudflare usually propagates in under a minute. If a record returns nothing, the cloud icon is most likely orange — check the dashboard.

## After Terraform deploys

You will not know the real FTDv outside IP until `terraform apply` finishes. Read it and update each A record.

```bash
cd infra
TARGET_IP=$(terraform output -raw ftdv_outside_public_ip)
echo "$TARGET_IP"
```

Update via the Cloudflare UI (edit each record, replace `1.1.1.1` with the new IP, save) or via the API. The API version for one record:

```bash
curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$VPN_RECORD_ID" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"name\":\"vpn\",\"content\":\"$TARGET_IP\",\"proxied\":false}"
```

You need the per-record IDs to use the API path. The UI is faster for three records.

After updating, re-run the dig loop. Each should now return the real FTDv outside IP, not `1.1.1.1`.
