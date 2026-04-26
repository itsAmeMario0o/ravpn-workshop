#!/usr/bin/env bash
set -euo pipefail

# Post-deploy smoke test.
#
# Walks the verification checklist from CLAUDE.md as a script so you don't
# have to remember every check by hand. Run after `terraform apply` and
# after the trading app has been deployed.
#
# What it checks:
#   1. Terraform outputs are readable (proves apply finished cleanly).
#   2. The resource group exists and has the expected VMs.
#   3. All three VMs are in the running state.
#   4. DNS resolves vpn.rooez.com and trading.rooez.com to the FTDv outside IP.
#   5. The FTDv outside IP is reachable on TCP 443 from this machine.
#   6. The cert presented at the FTDv outside contains both expected SANs.
#
# Each check prints OK or FAIL with a one-line reason. The summary at the
# bottom counts them. Exit code is non-zero if any check fails.
#
# Usage:
#   scripts/smoke-test.sh
#   RG=rg-ravpn-demo scripts/smoke-test.sh   # different resource group

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RG="${RG:-rg-ravpn-demo}"

ok=0
fail=0

if [[ -t 1 ]]; then
  green='\033[32m'; red='\033[31m'; reset='\033[0m'
else
  green=''; red=''; reset=''
fi

pass() { printf "${green}[OK]${reset}    %s\n" "$1"; ok=$((ok+1)); }
miss() { printf "${red}[FAIL]${reset}  %s\n" "$1"; fail=$((fail+1)); }

# 1. Terraform outputs. If terraform apply has not been run, this fails
# early and the rest of the script bails out.
cd "${REPO_ROOT}/infra"
if ! ftdv_ip=$(terraform output -raw ftdv_outside_public_ip 2>/dev/null); then
  miss "terraform output: cannot read ftdv_outside_public_ip. has terraform apply run yet?"
  printf "\nsummary: %d OK, %d FAIL\n" "${ok}" "${fail}"
  exit 1
fi
pass "terraform output: ftdv_outside_public_ip=${ftdv_ip}"
cd "${REPO_ROOT}"

# 2. Resource group exists. We check via az; if the user is signed in to
# a different subscription, this catches the mismatch.
if az group show -n "${RG}" >/dev/null 2>&1; then
  pass "resource group: ${RG} exists"
else
  miss "resource group: ${RG} not found in active subscription"
fi

# 3. VM running state. All three VMs (FTDv, ISE, app) must be running.
# `az vm get-instance-view` returns the power state under .statuses[1] in
# practice, but we ask for it via a defined query rather than relying on
# array indexing.
check_vm_running() {
  local vm="$1"
  local state
  state=$(az vm get-instance-view -g "${RG}" -n "${vm}" \
    --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus | [0]" \
    -o tsv 2>/dev/null || echo "")
  if [[ "${state}" == "VM running" ]]; then
    pass "vm ${vm}: running"
  else
    miss "vm ${vm}: ${state:-not found}"
  fi
}
check_vm_running "vm-ftdv"
check_vm_running "vm-ise"
check_vm_running "vm-tradingapp"

# 4. DNS resolution. Both hostnames must resolve to the FTDv outside IP.
# A mismatch usually means Cloudflare A records still point at the
# placeholder IP, or proxying (orange cloud) is on.
check_dns() {
  local fqdn="$1"
  local resolved
  resolved=$(dig +short "${fqdn}" @1.1.1.1 2>/dev/null | head -1)
  if [[ "${resolved}" == "${ftdv_ip}" ]]; then
    pass "dns ${fqdn}: ${resolved}"
  elif [[ -z "${resolved}" ]]; then
    miss "dns ${fqdn}: no answer. record may be missing or proxied."
  else
    miss "dns ${fqdn}: ${resolved} (expected ${ftdv_ip})"
  fi
}
check_dns "vpn.rooez.com"
check_dns "trading.rooez.com"

# 5. FTDv reachable on 443. We use openssl s_client with a 5 second
# timeout because curl on macOS does not have a clean way to test "TCP
# connectable but cert untrusted" without flags that vary by version.
if echo | openssl s_client -connect "${ftdv_ip}:443" -servername vpn.rooez.com \
   -connect_timeout 5 </dev/null >/dev/null 2>&1; then
  pass "ftdv outside ${ftdv_ip}:443 reachable"
else
  miss "ftdv outside ${ftdv_ip}:443 unreachable. check NSG and FTDv access policy."
fi

# 6. Cert SAN check. Pull whatever cert FTDv presents on 443 and confirm
# both expected SANs are listed. Catches "I forgot to bind the cert" and
# "the wrong cert was uploaded" in one shot.
cert_text=$(echo | openssl s_client -connect "${ftdv_ip}:443" -servername vpn.rooez.com \
  -connect_timeout 5 </dev/null 2>/dev/null | openssl x509 -noout -text 2>/dev/null || echo "")
if [[ -n "${cert_text}" ]]; then
  if grep -q "DNS:vpn.rooez.com" <<<"${cert_text}" && grep -q "DNS:trading.rooez.com" <<<"${cert_text}"; then
    pass "ftdv cert: both SANs present"
  elif grep -q "DNS:\*.rooez.com" <<<"${cert_text}"; then
    pass "ftdv cert: wildcard SAN present"
  else
    miss "ftdv cert: expected SANs missing. is the right cert bound to the connection profile?"
  fi
else
  miss "ftdv cert: could not retrieve. probably a network issue."
fi

# Summary.
printf "\nsummary: %d OK, %d FAIL\n" "${ok}" "${fail}"

if [[ "${fail}" -gt 0 ]]; then
  exit 1
fi
exit 0
