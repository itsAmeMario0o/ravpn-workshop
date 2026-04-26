# Prerequisites

What you need before starting.

## Accounts

- Azure subscription with quota for Standard_D8s_v3 (8 vCPU) and Standard_D8s_v4 (8 vCPU).
- Cisco Smart Account.
- Security Cloud Control tenant with cdFMC provisioned.
- Cloudflare account managing `rooez.com`.
- GitHub account with access to this repo.

## Local tools

| Tool | Minimum version | Install |
|---|---|---|
| Terraform | 1.5.0 | `brew install terraform` |
| Azure CLI | 2.60 | `brew install azure-cli` |
| Node.js | 20 | `brew install node` |
| Python | 3.12 | `brew install python@3.12` |
| certbot | 2.x | `brew install certbot` |
| jq | 1.7 | `brew install jq` |
| pre-commit | 3.x | `brew install pre-commit` |

## Verify

```bash
terraform version    # >= 1.5.0
az --version         # >= 2.60
node --version       # >= 20
python3 --version    # >= 3.12
certbot --version    # any 2.x
jq --version         # any
pre-commit --version # any
```

## Azure CLI login

```bash
az login
az account show
az account set --subscription "<subscription-name-or-id>"
```

## Verify

```bash
az account show --query name -o tsv
```

Expected: your subscription name.
