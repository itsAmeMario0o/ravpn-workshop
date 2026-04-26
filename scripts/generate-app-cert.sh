#!/usr/bin/env bash
set -euo pipefail

# Generates the self-signed cert and key the trading app uses for backend TLS.
# Two consumers need the same cert + key pair:
#   - The trading app VM (nginx serves it on the inside subnet).
#   - cdFMC, uploaded as an Internal Cert and bound to the ZTAA application.
#
# Generating locally keeps a single source of truth so re-deploys don't drift.
#
# Output:
#   certs/app/trading.crt
#   certs/app/trading.key
#
# Usage:
#   scripts/generate-app-cert.sh           # generate if missing
#   scripts/generate-app-cert.sh --force   # regenerate, overwriting

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/certs/app"
CERT="${OUT_DIR}/trading.crt"
KEY="${OUT_DIR}/trading.key"

log() { echo "[$1] $2"; }

force=0
[[ "${1:-}" == "--force" ]] && force=1

if [[ -f "${CERT}" && -f "${KEY}" && ${force} -eq 0 ]]; then
  log INFO "cert already exists at ${CERT}"
  log INFO "use --force to regenerate"
  exit 0
fi

if ! command -v openssl >/dev/null; then
  log ERROR "openssl not found"
  exit 1
fi

mkdir -p "${OUT_DIR}"

log INFO "generating self-signed cert (CN=trading-internal, 825 days)..."
openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
  -keyout "${KEY}" \
  -out "${CERT}" \
  -subj "/CN=trading-internal" \
  2>/dev/null

chmod 600 "${KEY}"
chmod 644 "${CERT}"

log INFO "cert: ${CERT}"
log INFO "key:  ${KEY}"
log INFO "next steps:"
log INFO "  1. scripts/deploy-trading-app.sh will push this pair to the app VM."
log INFO "  2. upload both files to cdFMC: Objects > Object Management > PKI > Internal Certs > Add."
