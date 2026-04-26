#!/usr/bin/env bash
set -euo pipefail

# Generates a Let's Encrypt wildcard SAN cert covering rooez.com and any
# subdomain of it. The DNS-01 challenge runs against Cloudflare. The cert
# is uploaded to cdFMC later as the identity cert (the one Cisco Secure
# Client and the user's browser see).
#
# Why wildcard: a single cert covers vpn.rooez.com, trading.rooez.com,
# ise.rooez.com, and anything else added later. New ZTAA-protected apps
# need only a Cloudflare A record - no cert reissue, no re-binding.
#
# Required env vars:
#   CF_API_TOKEN   Cloudflare API token with DNS edit on rooez.com
#   EMAIL          Email address for the Let's Encrypt ACME account.
#                  This is just where renewal warnings go - it does not
#                  need to be at the domain you are issuing for.
#
# Optional:
#   STAGING=1      Use Let's Encrypt staging endpoint while iterating
#   FORCE=1        Pass --force-renewal to certbot. Needed when going from a
#                  staging cert to production at the same path: certbot
#                  treats the existing staging cert as still valid and skips
#                  reissuance unless forced.
#   OUT_DIR        Output directory (default: ./certs)
#
# Usage:
#   STAGING=1 scripts/generate-certs.sh           # validate the chain first
#   FORCE=1 scripts/generate-certs.sh             # promote to production
#   scripts/generate-certs.sh                     # plain run (will skip if a
#                                                 # valid cert already exists)

CF_API_TOKEN="${CF_API_TOKEN:?CF_API_TOKEN must be set}"
EMAIL="${EMAIL:?EMAIL must be set}"
OUT_DIR="${OUT_DIR:-./certs}"
# The cert covers the apex domain and any subdomain via a wildcard. That
# means vpn.rooez.com, trading.rooez.com, ise.rooez.com, and anything else
# under rooez.com are all valid. The apex itself (rooez.com) is included
# as a separate SAN because wildcards do not match the bare domain.
DOMAINS=(rooez.com "*.rooez.com")

log() { echo "[$1] $2"; }

if ! command -v certbot >/dev/null; then
  log ERROR "certbot not installed. brew install certbot or apt install certbot"
  exit 1
fi

mkdir -p "${OUT_DIR}"
CONFIG_DIR="${OUT_DIR}/config"
WORK_DIR="${OUT_DIR}/work"
LOGS_DIR="${OUT_DIR}/logs"
mkdir -p "${CONFIG_DIR}" "${WORK_DIR}" "${LOGS_DIR}"

CF_INI="${OUT_DIR}/cloudflare.ini"
umask 077
cat >"${CF_INI}" <<EOF
dns_cloudflare_api_token = ${CF_API_TOKEN}
EOF
chmod 600 "${CF_INI}"

ARGS=(
  certonly
  --dns-cloudflare
  --dns-cloudflare-credentials "${CF_INI}"
  --dns-cloudflare-propagation-seconds 30
  --non-interactive
  --agree-tos
  --email "${EMAIL}"
  --config-dir "${CONFIG_DIR}"
  --work-dir "${WORK_DIR}"
  --logs-dir "${LOGS_DIR}"
  --cert-name ravpn-demo
)

for d in "${DOMAINS[@]}"; do
  ARGS+=(-d "${d}")
done

if [[ "${STAGING:-0}" == "1" ]]; then
  ARGS+=(--staging)
  log INFO "using Let's Encrypt staging endpoint"
fi

if [[ "${FORCE:-0}" == "1" ]]; then
  ARGS+=(--force-renewal)
  log INFO "force-renewal enabled (will reissue even if existing cert is valid)"
fi

log INFO "requesting cert for: ${DOMAINS[*]}"
certbot "${ARGS[@]}"

CERT_PATH="${CONFIG_DIR}/live/ravpn-demo"
log INFO "cert written to ${CERT_PATH}/fullchain.pem and privkey.pem"
log INFO "verify both SANs with: openssl x509 -in ${CERT_PATH}/fullchain.pem -noout -text | grep DNS"
