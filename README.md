# RAVPN Workshop

A self-contained Azure environment that demos remote access VPN on FTD with cdFMC (cloud-delivered FMC) management, plus geolocation VPN and Zero Trust Application Access on the same box. Four working demos, one whiteboard discussion, and enough infrastructure-as-code to rebuild the whole thing in a couple of hours.

## Documentation site

**[https://itsAmeMario0o.github.io/ravpn-workshop/](https://itsAmeMario0o.github.io/ravpn-workshop/)**

A guided walkthrough of the architecture, the four demos, the six-phase build, and the teardown. Written for an audience without a deep network or security background. The files in `setup/` remain the source of truth for exact commands.

## What it shows

- **Remote access VPN on FTD.** A user opens Cisco Secure Client, signs in, and lands on a fictitious trading dashboard. The firewall (FTDv) terminates the tunnel. ISE handles RADIUS. Entra ID validates the password. No tunnel, no dashboard.
- **cdFMC management.** All FTD policy and monitoring lives in cloud-delivered FMC, reached through Security Cloud Control. The same dashboard shows the active VPN sessions, the geographies, and the Secure Client versions.
- **Geolocation VPN.** Two connection profiles on the same firewall apply different policy based on where the client is connecting from. The cdFMC dashboard shows the geographic mix.
- **Zero Trust Application Access (ZTAA).** A user opens a browser, hits the same dashboard, and the firewall acts as a zero-trust broker. SAML to Entra, MFA via Authenticator, and back to the app. No VPN client involved.
- **Multi-instance (whiteboard only).** A short discussion of FTD multi-instance on Firepower 4100/4200 for hardware-isolated workloads. Not deployed.

## Repository layout

```
ravpn-workshop/
├── CLAUDE.md            Project guide for Claude Code
├── PLAN.md              24-hour build plan with validation gates
├── azure-demo-plan.md   Detailed architecture reference
├── docs/                Jekyll source for the GitHub Pages site
├── infra/               Terraform for Azure (FTDv, ISE, app, network, Bastion)
├── app/                 React/Vite trading dashboard with /vpn and /ztaa routes
├── scripts/             Deploy, certs, Bastion tunnel helpers
├── setup/               Step-by-step build guide
└── .github/workflows/   CI: terraform fmt/validate, gitleaks; Pages deploy
```

## Where to start

For a guided read, open the [documentation site](https://itsAmeMario0o.github.io/ravpn-workshop/). For the engineering view, read [`PLAN.md`](PLAN.md) for the phased build with validation gates, then work through [`setup/README.md`](setup/README.md) for the actual instructions. The setup guide is written so you can follow it without having deployed FTDv or ISE on Azure before.

If something fails in a way you can't immediately explain, check [`LESSONS-LEARNED.md`](LESSONS-LEARNED.md) first — it captures the gotchas we hit during the build (Cisco, Azure, Entra portal navigation drift, Terraform, local toolchain).

## Cost warning

The FTDv and ISE VMs are the dominant cost drivers — both run on 8 vCPU SKUs. Leaving the environment up for a week consumes a real budget. When the workshop ends, run `terraform destroy` from `infra/` and confirm the resource group is gone.

## License

See [LICENSE](LICENSE).
