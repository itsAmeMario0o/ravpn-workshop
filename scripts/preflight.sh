#!/usr/bin/env bash
set -euo pipefail

# Pre-deploy readiness check.
#
# Runs every Phase 0 verification in one shot so you can see in 30 seconds
# whether the environment is ready to `terraform apply` or whether
# something still needs attention. Read-only - does not change anything.
#
# What it checks:
#   1. Azure CLI is signed in.
#   2. The active subscription is set.
#   3. Regional vCPU quota is enough for the three demo VMs (17 vCPU total).
#   4. Per-family quota for DSv3 (FTDv), DSv4 (ISE), and BS (app).
#   5. Marketplace terms accepted for FTD 10 and ISE 3.5.
#   6. Local toolchain present (terraform, node, certbot, openssl, jq).
#   7. Terraform fmt and validate are clean inside infra/.
#   8. App typecheck and tests pass.
#   9. Cert env vars set (warning only - needed for Phase 1 cert work).
#   10. Cert files generated locally (warning only - needed before deploy).
#
# Output:
#   Each check prints OK, WARN, or FAIL with a one-line reason.
#   A summary line at the bottom counts each.
#
# Exit code:
#   0 if all FAIL counts are zero (warnings are fine).
#   1 if any check fails.
#
# Usage:
#   scripts/preflight.sh
#   LOCATION=westus2 scripts/preflight.sh   # check a different region

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCATION="${LOCATION:-eastus2}"
EXPECTED_TOTAL_VCPU=17  # FTDv 8 + ISE 8 + app 1

# Counters for the summary line at the end.
ok=0
warn=0
fail=0

# Coloured output if the terminal supports it. Plain text otherwise so the
# script is readable when piped to a file or run from CI.
if [[ -t 1 ]]; then
  green='\033[32m'; yellow='\033[33m'; red='\033[31m'; reset='\033[0m'
else
  green=''; yellow=''; red=''; reset=''
fi

pass() { printf "${green}[OK]${reset}    %s\n" "$1"; ok=$((ok+1)); }
warn() { printf "${yellow}[WARN]${reset}  %s\n" "$1"; warn=$((warn+1)); }
miss() { printf "${red}[FAIL]${reset}  %s\n" "$1"; fail=$((fail+1)); }

# 1. Azure login state. `az account show` returns a non-zero exit code if
# you have not run `az login` recently, which is the simplest way to test.
if user=$(az account show --query "user.name" -o tsv 2>/dev/null) && [[ -n "${user}" ]]; then
  pass "azure login: ${user}"
else
  miss "azure login: not signed in. run 'az login' first."
fi

# 2. Active subscription. We can't tell which subscription is "right", but
# we can show the user which one they are about to deploy into.
if sub=$(az account show --query "name" -o tsv 2>/dev/null) && [[ -n "${sub}" ]]; then
  pass "subscription: ${sub}"
else
  miss "subscription: none active. run 'az account set' first."
fi

# 3. Regional vCPU cap. This is a higher-level limit that gates ALL VMs in
# the region regardless of family. If this is too low, the per-family
# quotas don't matter.
total_limit=$(az vm list-usage -l "${LOCATION}" --query "[?name.value=='cores'].limit | [0]" -o tsv 2>/dev/null || echo 0)
if [[ -z "${total_limit}" || "${total_limit}" -lt "${EXPECTED_TOTAL_VCPU}" ]]; then
  miss "regional vCPU cap in ${LOCATION}: ${total_limit:-unknown} (need >= ${EXPECTED_TOTAL_VCPU})"
else
  pass "regional vCPU cap in ${LOCATION}: ${total_limit} (need >= ${EXPECTED_TOTAL_VCPU})"
fi

# 4. Per-family vCPU caps. Each family must have at least the size of one
# VM in that family available.
check_family() {
  local family="$1" need="$2"
  local limit
  limit=$(az vm list-usage -l "${LOCATION}" --query "[?contains(name.value, '${family}')].limit | [0]" -o tsv 2>/dev/null || echo 0)
  if [[ -z "${limit}" || "${limit}" -lt "${need}" ]]; then
    miss "${family} cap in ${LOCATION}: ${limit:-unknown} (need >= ${need})"
  else
    pass "${family} cap in ${LOCATION}: ${limit} (need >= ${need})"
  fi
}
check_family "standardDSv3Family" 8
check_family "standardDSv4Family" 8
check_family "standardBSFamily"   1

# 5. Marketplace terms. We check the two SKUs the deploy actually uses.
# Marketplace terms are per-SKU - accepting one does not carry over.
check_terms() {
  local plan="$1" offer="$2"
  local accepted
  accepted=$(az vm image terms show --publisher cisco --offer "${offer}" --plan "${plan}" --query "accepted" -o tsv 2>/dev/null || echo "false")
  if [[ "${accepted}" == "true" ]]; then
    pass "marketplace terms ${plan}: accepted"
  else
    miss "marketplace terms ${plan}: NOT accepted. run: az vm image terms accept --publisher cisco --offer ${offer} --plan ${plan}"
  fi
}
check_terms "cisco-ftdv-x86-byol" "cisco-ftdv"
check_terms "cisco-ise_3_5"       "cisco-ise-virtual"

# 6. Local toolchain. We do not enforce minimum versions here - the setup
# guide does that. The point is to surface "you forgot to install X."
check_tool() {
  local tool="$1"
  if command -v "${tool}" >/dev/null; then
    pass "${tool}: $(command -v "${tool}")"
  else
    miss "${tool}: not installed"
  fi
}
for t in terraform node npm python3 certbot openssl jq pre-commit; do
  check_tool "${t}"
done

# 7. Terraform fmt and validate inside infra/. The validate step needs the
# providers downloaded, so we run init -backend=false first if no .terraform
# directory exists yet.
if [[ -d "${REPO_ROOT}/infra" ]]; then
  if (cd "${REPO_ROOT}/infra" && terraform fmt -check -recursive >/dev/null 2>&1); then
    pass "terraform fmt: clean"
  else
    miss "terraform fmt: needs reformatting. run: cd infra && terraform fmt -recursive"
  fi

  if [[ ! -d "${REPO_ROOT}/infra/.terraform" ]]; then
    (cd "${REPO_ROOT}/infra" && terraform init -backend=false >/dev/null 2>&1) || true
  fi
  if (cd "${REPO_ROOT}/infra" && terraform validate >/dev/null 2>&1); then
    pass "terraform validate: clean"
  else
    miss "terraform validate: errors. run: cd infra && terraform validate"
  fi
else
  miss "infra/ directory missing"
fi

# 8. App typecheck and tests. The app does not need to be deployed to
# verify it compiles - we just run the same checks CI runs.
if [[ -d "${REPO_ROOT}/app" ]]; then
  if [[ ! -d "${REPO_ROOT}/app/node_modules" ]]; then
    warn "app: node_modules missing. run 'npm install' inside app/ before deploy."
  else
    if (cd "${REPO_ROOT}/app" && npx tsc --noEmit >/dev/null 2>&1); then
      pass "app tsc: clean"
    else
      miss "app tsc: errors. run: cd app && npx tsc --noEmit"
    fi
    if (cd "${REPO_ROOT}/app" && npx vitest run >/dev/null 2>&1); then
      pass "app tests: pass"
    else
      miss "app tests: failing. run: cd app && npx vitest run"
    fi
  fi
else
  miss "app/ directory missing"
fi

# 9. Cert env vars. These are warnings rather than failures because the
# user only needs them right before running the cert generation script.
if [[ -n "${CF_API_TOKEN:-}" ]]; then
  pass "CF_API_TOKEN: set"
else
  warn "CF_API_TOKEN: not set. needed by scripts/generate-certs.sh."
fi

if [[ -n "${EMAIL:-}" ]]; then
  pass "EMAIL: set"
else
  warn "EMAIL: not set. needed by scripts/generate-certs.sh as the Let's Encrypt account contact."
fi

# 10. Cert files. Both certs must exist locally before deploy. Warnings
# rather than failures because preflight is run early in the flow.
if [[ -f "${REPO_ROOT}/certs/config/live/ravpn-demo/fullchain.pem" ]]; then
  pass "identity cert: present"
else
  warn "identity cert: missing. run scripts/generate-certs.sh."
fi

if [[ -f "${REPO_ROOT}/certs/app/trading.crt" && -f "${REPO_ROOT}/certs/app/trading.key" ]]; then
  pass "application cert: present"
else
  warn "application cert: missing. run scripts/generate-app-cert.sh."
fi

# Summary.
printf "\nsummary: %d OK, %d WARN, %d FAIL\n" "${ok}" "${warn}" "${fail}"

if [[ "${fail}" -gt 0 ]]; then
  exit 1
fi
exit 0
