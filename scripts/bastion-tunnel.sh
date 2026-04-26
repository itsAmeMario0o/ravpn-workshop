#!/usr/bin/env bash
set -euo pipefail

# Opens a Bastion SSH tunnel to a target VM in the demo resource group.
#
# Usage:
#   scripts/bastion-tunnel.sh <target> [local-port]
#
# Targets:
#   ftdv   FTDv management interface (port 22)
#   ise    ISE node (port 22 for CLI; ISE GUI is on the same IP at 443)
#   app    Trading app VM (port 22)
#
# Examples:
#   scripts/bastion-tunnel.sh ftdv          # tunnel to 127.0.0.1:50022
#   scripts/bastion-tunnel.sh ise 50443     # tunnel ISE GUI to 127.0.0.1:50443
#
# Then in another terminal:
#   ssh -p 50022 admin@127.0.0.1
#   open https://127.0.0.1:50443

RG="${RG:-rg-ravpn-demo}"
BASTION="${BASTION:-bastion-demo}"

target="${1:?target required: ftdv|ise|app}"
local_port="${2:-50022}"

case "${target}" in
  ftdv) vm="vm-ftdv"; resource_port=22 ;;
  ise)  vm="vm-ise"; resource_port="${ISE_PORT:-22}" ;;
  app)  vm="vm-tradingapp"; resource_port=22 ;;
  *)    echo "[ERROR] unknown target: ${target}"; exit 1 ;;
esac

vm_id="$(az vm show -g "${RG}" -n "${vm}" --query id -o tsv)"
[[ -n "${vm_id}" ]] || { echo "[ERROR] VM ${vm} not found in ${RG}"; exit 1; }

echo "[INFO] tunneling ${vm}:${resource_port} to 127.0.0.1:${local_port}"
echo "[INFO] press Ctrl+C to close the tunnel"
exec az network bastion tunnel \
  --name "${BASTION}" \
  --resource-group "${RG}" \
  --target-resource-id "${vm_id}" \
  --resource-port "${resource_port}" \
  --port "${local_port}"
