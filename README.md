# RAVPN Workshop

A self-contained Azure environment for demonstrating Cisco Secure Access. Four working demos, one whiteboard discussion, and enough infrastructure-as-code to rebuild the whole thing in a couple of hours.

## What it shows

- **RAVPN.** A user opens Cisco Secure Client, signs in, and lands on a fictitious trading dashboard. The firewall (FTDv) terminates the tunnel. ISE handles RADIUS. Entra ID validates the password. No tunnel, no dashboard.
- **Geolocation VPN.** Two connection profiles on the same firewall apply different policy based on where the client is connecting from. The cdFMC dashboard shows the geographic mix.
- **ZTAA (Zero Trust Application Access).** A user opens a browser, hits the same dashboard, and the firewall acts as a zero-trust broker. SAML to Entra, MFA via Authenticator, and back to the app. No VPN client involved.
- **cdFMC VPN dashboard.** Sessions, geographies, Secure Client versions, all live.
- **Multi-instance (whiteboard only).** A short discussion of FTD multi-instance on Firepower 4100/4200 for hardware-isolated workloads. Not deployed.

## Repository layout

```
ravpn-workshop/
├── CLAUDE.md            Project guide for Claude Code
├── PLAN.md              24-hour build plan with validation gates
├── azure-demo-plan.md   Detailed architecture reference
├── infra/               Terraform for Azure (FTDv, ISE, app, network, Bastion)
├── app/                 React/Vite trading dashboard with /vpn and /ztaa routes
├── scripts/             Deploy, certs, Bastion tunnel helpers
├── setup/               Step-by-step build guide
└── .github/workflows/   CI: terraform fmt/validate, gitleaks
```

## Where to start

Read [`PLAN.md`](PLAN.md) for the phased build with validation gates, then work through [`setup/README.md`](setup/README.md) for the actual instructions. The setup guide is written so you can follow it without having deployed FTDv or ISE on Azure before.

## Cost warning

The FTDv and ISE VMs are the dominant cost drivers — both run on 8 vCPU SKUs. Leaving the environment up for a week consumes a real budget. When the workshop ends, run `terraform destroy` from `infra/` and confirm the resource group is gone.

## License

See [LICENSE](LICENSE).
