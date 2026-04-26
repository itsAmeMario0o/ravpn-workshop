#!/usr/bin/env bash
set -euo pipefail

# Builds the React app, copies the dist/ output to the trading app VM via
# Bastion-tunneled SSH, and configures nginx to serve it over HTTPS using
# a self-signed cert (for backend TLS to ZTAA enforcement).
#
# Required env vars:
#   RG                 Resource group name (default: rg-ravpn-workshop)
#   APP_VM             App VM name (default: vm-app)
#   APP_USER           SSH user on the app VM
#   BASTION            Bastion name (default: bastion-ravpn)
#   APP_PRIVATE_IP     App VM private IP (default: 10.100.3.20)
#
# Usage:
#   scripts/deploy-trading-app.sh

RG="${RG:-rg-ravpn-workshop}"
APP_VM="${APP_VM:-vm-app}"
APP_USER="${APP_USER:?APP_USER must be set}"
BASTION="${BASTION:-bastion-ravpn}"
APP_PRIVATE_IP="${APP_PRIVATE_IP:-10.100.3.20}"
TUNNEL_PORT="${TUNNEL_PORT:-50022}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${REPO_ROOT}/app"
DIST_DIR="${APP_DIR}/dist"

log() { echo "[$1] $2"; }

log INFO "building React app..."
cd "${APP_DIR}"
npm ci
npm run build
[[ -d "${DIST_DIR}" ]] || { log ERROR "build did not produce ${DIST_DIR}"; exit 1; }

log INFO "starting Bastion tunnel to ${APP_VM} on port ${TUNNEL_PORT}..."
APP_VM_ID="$(az vm show -g "${RG}" -n "${APP_VM}" --query id -o tsv)"
az network bastion tunnel \
  --name "${BASTION}" \
  --resource-group "${RG}" \
  --target-resource-id "${APP_VM_ID}" \
  --resource-port 22 \
  --port "${TUNNEL_PORT}" &
TUNNEL_PID=$!
trap 'kill "${TUNNEL_PID}" 2>/dev/null || true' EXIT
sleep 5

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p ${TUNNEL_PORT}"
SCP_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P ${TUNNEL_PORT}"

log INFO "preparing remote directories..."
ssh ${SSH_OPTS} "${APP_USER}@127.0.0.1" "sudo mkdir -p /var/www/trading && sudo chown -R ${APP_USER}:${APP_USER} /var/www/trading"

log INFO "syncing dist/ to app VM..."
tar -C "${DIST_DIR}" -czf - . | ssh ${SSH_OPTS} "${APP_USER}@127.0.0.1" "tar -C /var/www/trading -xzf -"

log INFO "writing nginx config..."
ssh ${SSH_OPTS} "${APP_USER}@127.0.0.1" 'sudo tee /etc/nginx/sites-available/trading >/dev/null' <<'NGINX'
server {
    listen 443 ssl http2;
    server_name _;

    ssl_certificate     /etc/ssl/certs/trading.crt;
    ssl_certificate_key /etc/ssl/private/trading.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    root /var/www/trading;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}

server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}
NGINX

log INFO "generating self-signed cert (used for backend TLS only; FTD presents the public cert)..."
ssh ${SSH_OPTS} "${APP_USER}@127.0.0.1" 'sudo openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
  -keyout /etc/ssl/private/trading.key \
  -out /etc/ssl/certs/trading.crt \
  -subj "/CN=trading-internal" 2>/dev/null && \
  sudo chmod 600 /etc/ssl/private/trading.key'

log INFO "enabling site and reloading nginx..."
ssh ${SSH_OPTS} "${APP_USER}@127.0.0.1" '
  sudo ln -sf /etc/nginx/sites-available/trading /etc/nginx/sites-enabled/trading
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo nginx -t
  sudo systemctl reload nginx
'

log INFO "deploy complete. test from inside subnet: curl -k https://${APP_PRIVATE_IP}/vpn"
