#!/usr/bin/env bash
set -euo pipefail

# Generates a Let's Encrypt SAN cert for vpn.rooez.com and trading.rooez.com
# using the DNS-01 challenge against Cloudflare. The cert is later uploaded
# to FTDv via cdFMC.
#
# Required env vars:
#   CF_API_TOKEN   Cloudflare API token with DNS edit on rooez.com
#   EMAIL          Email address for the Let's Encrypt account
#
# Optional:
#   STAGING=1      Use Let's Encrypt staging endpoint while iterating
#   OUT_DIR        Output directory (default: ./certs)
#
# Usage:
#   STAGING=1 scripts/generate-certs.sh
#   scripts/generate-certs.sh   # production once you trust the chain

CF_API_TOKEN="${CF_API_TOKEN:?CF_API_TOKEN must be set}"
EMAIL="${EMAIL:?EMAIL must be set}"
OUT_DIR="${OUT_DIR:-./certs}"
DOMAINS=(vpn.rooez.com trading.rooez.com)

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
  --cert-name ravpn-workshop
)

for d in "${DOMAINS[@]}"; do
  ARGS+=(-d "${d}")
done

if [[ "${STAGING:-0}" == "1" ]]; then
  ARGS+=(--staging)
  log INFO "using Let's Encrypt staging endpoint"
fi

log INFO "requesting cert for: ${DOMAINS[*]}"
certbot "${ARGS[@]}"

CERT_PATH="${CONFIG_DIR}/live/ravpn-workshop"
log INFO "cert written to ${CERT_PATH}/fullchain.pem and privkey.pem"
log INFO "verify both SANs with: openssl x509 -in ${CERT_PATH}/fullchain.pem -noout -text | grep DNS"
