# Prerequisites

This step is about confirming you have everything before you start spending money on Azure VMs. The build later assumes all of this is in place. If anything is missing, the deploy will fail in a way that costs you time.

## Accounts you need

- An **Azure subscription** with quota for two larger VM families (Standard_D8s_v3 for FTDv, Standard_D8s_v4 for ISE). Quota is per region; check before you commit to a region.
- A **Cisco Smart Account**. The FTDv image is BYOL, which means it expects to phone home to Smart Licensing eventually. cdFMC handles the licensing once the device is registered.
- A **Security Cloud Control tenant** with cdFMC provisioned. The registration command and NAT ID come from there.
- A **Cloudflare account** managing the DNS for `rooez.com`. We use the Cloudflare DNS-01 challenge for Let's Encrypt and we set the A records that point at the firewall.
- A **GitHub account** with access to this repo so you can clone and push.

## Local tools

| Tool | Minimum version | Install on macOS |
|---|---|---|
| Terraform | 1.5.0 | `brew install terraform` |
| Azure CLI | 2.60 | `brew install azure-cli` |
| Node.js | 20 | `brew install node` |
| Python | 3.12 | `brew install python@3.12` |
| certbot | 2.x | `brew install certbot` |
| jq | 1.7 | `brew install jq` |
| pre-commit | 3.x | `brew install pre-commit` |

If you are on Linux, the package names are similar in `apt` or `dnf`. The minimum versions are the only thing that matters.

## Verify

Run each command. Compare the output to the minimum version above.

```bash
terraform version
az --version
node --version
python3 --version
certbot --version
jq --version
pre-commit --version
```

## Sign in to Azure

```bash
az login
az account show
az account set --subscription "<subscription-name-or-id>"
```

`az login` opens a browser. After you sign in, `az account show` should print details for the subscription you intend to use. If you have more than one subscription, `az account set` switches the active one.

## Verify

```bash
az account show --query name -o tsv
```

You should see the name of the subscription you just set. If the wrong subscription is active, every later step will deploy to the wrong place.
