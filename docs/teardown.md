---
layout: default
title: Teardown
permalink: /teardown/
eyebrow: Stop
summary: The two big virtual machines run on hourly billing. When the workshop ends, take it down. A weekend of forgetting will cost real money.
---

## Why this page matters

The two big virtual machines (the firewall and the identity server) sit on 8-CPU sizes. Azure bills them by the hour. Azure Bastion adds about a dollar an hour on its own. Leaving the build up over a long weekend will quietly burn through a meaningful chunk of demo budget. None of it is dramatic. It just adds up.

## Order matters

The identity server was deployed by hand through the Azure Portal, not by Terraform. That means Terraform does not know it exists, and `terraform destroy` will skip it. Delete it first, then let Terraform clean up the rest.

## Step 1: Delete the identity server by hand

Run these in a terminal that is signed in to Azure:

```bash
az vm delete -g rg-ravpn-demo -n vm-ise --yes

az disk list -g rg-ravpn-demo \
  --query "[?starts_with(name, 'vm-ise_OsDisk')].name" -o tsv \
  | xargs -I{} az disk delete -g rg-ravpn-demo -n {} --yes

az network nic list -g rg-ravpn-demo \
  --query "[?contains(name, 'vm-ise')].name" -o tsv \
  | xargs -I{} az network nic delete -g rg-ravpn-demo --name {}
```

Three commands, three things being deleted: the virtual machine itself, the disk it was running on, and the network connection. Azure does not delete the disk or the network connection automatically when you delete the VM, so each one has to be removed by name.

## Step 2: Destroy the rest with Terraform

```bash
cd infra
terraform destroy
```

Terraform reads its records, lists everything it built, and asks you to confirm. Type `yes`. Wait. When it finishes, the whole resource group should be empty.

Open the Azure Portal afterwards and confirm that the resource group `rg-ravpn-demo` is gone. Sometimes one resource lingers and you can delete it manually.

## Step 3: Clean up outside Azure

The cloud manager and a couple of other services still hold references to the old build. Tidy these up so a future rebuild starts clean:

- **Cloud manager (cdFMC).** Inventory > Devices > delete the firewall entry. The cloud manager will refuse to register a new firewall under the same name otherwise.
- **Identity server side.** If you preserved it elsewhere (this build does not), remove the firewall as a registered client.
- **Cloudflare.** Delete the DNS records for `vpn.rooez.com` and `trading.rooez.com`.
- **Let's Encrypt.** Revoke the public certificate if you do not plan to reuse it. Reuse is fine. The same certificate works the next time you rebuild.

## What is safe to keep

A surprising amount survives a teardown without any consequence:

- The Terraform code in the repo.
- The React source for the dashboard.
- The local copies of the certificates.
- The Cisco Security Cloud Control tenant and the cloud manager itself.

The next time you rebuild, the only steps that have to happen again are `terraform apply`, the manual identity server deployment, and the cloud manager registration. Everything else is configuration that survives.

## A short note on cost discipline

Cloud demos are cheap if you treat them as ephemeral. They are expensive if you forget about them. Set a calendar reminder for the day after the workshop. Run the teardown. Confirm the resource group is gone. Move on.
