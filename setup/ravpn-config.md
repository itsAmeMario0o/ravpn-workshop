# cdFMC RAVPN configuration

The remote-access VPN is the centerpiece demo. Cisco Secure Client connects to FTDv on `vpn.rooez.com`, authenticates against Entra ID through ISE, and lands on the trading dashboard. This guide walks the cdFMC configuration that makes that happen.

## Before you start

- ISE is configured (`ise-config.md`) and the `RAVPN-Demo` policy set returns `PermitAccess` for traffic from our FTD.
- The Let's Encrypt cert (`tls-certs.md`) is installed on FTDv as `ravpn-identity`.
- The AAA Server Group `ISE-RADIUS` is built in cdFMC, pointing at `10.100.4.10` with the shared secret matching ISE's Network Device record for `ftdv-ravpn`.
- DNS A record `vpn.rooez.com` → FTDv outside public IP, gray cloud (DNS only) in Cloudflare.
- Cisco Secure Client is installed locally for testing, or a Secure Client `.pkg`/`.dmg`/`.msi` is uploaded to cdFMC under `Objects > Object Management > VPN > Secure Client File`.

## How the VPN address pool works

When a Secure Client connects, FTDv hands it an IP from a pool you define. That IP becomes the client's "inside-tunnel address" — every packet the user sends through the VPN sources from this IP. The user's laptop still has its real public IP from their home or office ISP, but inside the tunnel the laptop rides on the pool IP.

```
Mario's laptop [home ISP IP]
   │
   │ TLS tunnel to vpn.rooez.com:443
   ▼
[FTDv outside 10.100.2.10]   public Azure IP 20.114.157.202
   │
   │ FTDv says: "you're now 192.168.50.1 inside the tunnel"
   │
[FTDv inside 10.100.3.10]
   │
   ▼
[Trading app 10.100.3.20]
```

The pool is a logical IP range that exists only inside FTDv. Azure has no idea this range exists. That sounds harmless until you think about reply traffic — which is where most first-time VPN deployments break.

### The pool must not overlap with anything else

The pool can be any RFC 1918 range, but it cannot collide with subnets the VPN client needs to reach.

| Pool choice | Verdict | Why |
|---|---|---|
| `192.168.50.0/24` | ✅ Best | Outside our `10.100.0.0/16` VNet entirely. Visually distinct from VNet IPs in logs. |
| `172.16.50.0/24` | ✅ Fine | Different RFC 1918 family from the VNet. No overlap. |
| `10.100.50.0/24` | ❌ Don't | Inside the VNet `/16`. Even if the `.50` subnet doesn't exist today, future subnet allocations could conflict. |
| `10.100.3.0/24` | ❌ Hard no | Direct collision with the inside subnet. Routing breaks completely. |

We use `192.168.50.0/24` for the workshop. Pool range `192.168.50.1-192.168.50.50`, mask `255.255.255.0`. The `192.168.x.x` family also makes it instantly obvious in logs which traffic came from a VPN client.

### The reverse-traffic gotcha

Here is the trap that catches almost everyone the first time. When you connect over VPN and try to reach the trading app at `10.100.3.20`:

1. Your packet leaves Secure Client with source `192.168.50.1`, destination `10.100.3.20`. Encrypted, encapsulated, sent through the tunnel.
2. FTDv un-tunnels on the outside interface. Sees the inner packet: source `192.168.50.1`, destination `10.100.3.20`.
3. FTDv has a connected route to `10.100.3.0/24` via its inside interface, so it forwards the packet onto the inside subnet.
4. The trading app receives the packet. Source: `192.168.50.1`. Destination: `10.100.3.20`.
5. The trading app replies. The reply has source `10.100.3.20`, destination `192.168.50.1`.
6. The reply hits Azure's network stack. **Azure has no route for `192.168.50.0/24`.** Azure either drops the packet or sends it to the VNet's default gateway, where it disappears into the void.

Outbound through the tunnel works fine. The return trip breaks. Asymmetric routing. The user sees a hang and concludes "the VPN is broken" when in fact the auth and tunnel are perfect — only the reply path is missing.

### Two ways to fix the reverse-traffic problem

**Option 1: User Defined Route on the inside subnet (UDR).** Tell Azure how to reach the pool. Add a route on the inside subnet's route table sending `192.168.50.0/24` to FTDv's inside interface (`10.100.3.10`). Azure now knows where to send replies. The trading app continues to see the real per-user pool IPs (`192.168.50.1`, `192.168.50.2`, ...). Best when you want per-user logging or per-user policy on the inside application.

**Option 2: Source-NAT the VPN clients (PAT).** Configure FTDv to translate the VPN pool source IP to the FTDv inside interface IP (`10.100.3.10`) before the traffic leaves the inside interface. The trading app sees every VPN user as coming from `10.100.3.10`. Azure already knows how to reach `10.100.3.10` — it is a normal inside-subnet IP — so replies route back to FTDv through standard Azure routing. No UDRs. No route table changes. The cost is per-user IP visibility on the inside.

This workshop uses **Option 2 (PAT)**. It is the dominant production pattern for RAVPN, and it shows a complete architectural picture without forcing Azure routing changes that distract from the demo's main story.

### The NAT rule we add

After the wizard creates the connection profile and the policy deploys, we add one NAT rule in `Policies > NAT`. The rule rewrites VPN-sourced traffic so the inside subnet sees only the FTDv inside interface as the source.

| Field | Value | What it does |
|---|---|---|
| NAT Rule | Manual NAT Rule | Standard form for source-NAT entries. |
| Type | Dynamic | The pool maps to the interface IP via PAT (port translation). |
| Insert | Manual NAT Rules, Above | Manual rules evaluate before auto-NAT. Put this near the top so it always wins for VPN traffic. |
| Source Interface Objects | `outside` | VPN clients enter via the outside interface. |
| Destination Interface Objects | `inside` | Translation happens for traffic egressing to inside. |
| Original Source | network object covering `192.168.50.0/24` | Match VPN pool traffic. |
| Original Destination | `any` (or specifically `10.100.3.0/24`) | Translate any inside-bound traffic, or scope to the inside subnet for tighter rules. |
| Translated Source | **Destination Interface IP** | "Interface PAT" — translate to whatever IP the egress interface holds. For inside, that is `10.100.3.10`. |
| Translated Destination | original | We are not rewriting the destination. |

Translated Source = "Destination Interface IP" is the canonical Cisco term for what the rest of the world calls "Interface PAT" or "hide NAT." FTDv computes the translation at runtime based on whichever interface the packet leaves through, so if the inside interface IP changes the rule still works.

## How Secure Client knows your OS

When a client connects, FTDv has to pick the right platform image to serve. There is no magic — just a polite identification exchange in HTTP headers.

### Web-launch (browser, no client installed yet)

The user opens a browser and goes to `https://vpn.rooez.com`. The browser sends a User-Agent header that identifies the OS:

```
Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) ...   → FTDv serves the macOS package
Mozilla/5.0 (Windows NT 10.0; Win64; x64) ...      → FTDv serves the Windows package
```

If the matching platform's image is not uploaded to cdFMC, the user gets a download error. That is why you upload both platforms when your audience could be either.

### Already installed (Secure Client connecting)

When an installed Secure Client connects, it sends its own headers in the TLS handshake:

| Header | Example | What it tells FTDv |
|---|---|---|
| `User-Agent` | `Cisco AnyConnect VPN Agent for Mac OS X 14.5` | OS family and version |
| `X-AnyConnect-Platform` | `mac-intel`, `mac-arm`, `win`, `linux64` | Platform identifier |

FTDv uses these to match the right image for version comparison and auto-update, apply platform-specific group policy if you have any, and log the platform in connection events. That last one is what populates the "Secure Client version inventory" tile in cdFMC's RAVPN dashboard during the demo.

### Headend vs predeploy packages

For cdFMC's Secure Client Image library, upload the **headend / webdeploy** variant. The predeploy package is for IT installing Secure Client directly on endpoints (via Intune, JAMF, manual install) and is not designed for FTDv to consume. The filenames make this clear:

- `cisco-secure-client-macos-5.1.x.x-webdeploy-k9.pkg` ← upload this
- `cisco-secure-client-macos-5.1.x.x-predeploy-k9.dmg` ← skip; this is for endpoints

Same naming pattern for Windows.

## The wizard, page by page

The cdFMC Remote Access VPN Policy Wizard has 5 pages. Each one configures one slice of the RAVPN puzzle.

### Page 1: Policy Assignment

| Field | Value |
|---|---|
| Name | `RAVPN-Demo` |
| Description | (optional) `Workshop RAVPN — Entra ID via ISE` |
| VPN Protocols | ✅ SSL, ❌ **uncheck IPsec-IKEv2** |
| Targeted Devices | move `ftd-ravpn` from Available to Selected |

**Why uncheck IPsec-IKEv2:** the identity cert was imported with SSL Server and SSL Client validation usage, not IPsec. Leaving IPsec on adds an unconfigured protocol stack to the policy that will throw deploy warnings. We are doing pure SSL VPN.

### Page 2: Connection Profile

This is where AAA meets address assignment. It is the most field-dense page in the wizard.

| Field | Value | Why |
|---|---|---|
| Connection Profile Name | `RAVPN-Demo` | Doubles as the **connection alias** users can pick in Secure Client when multiple profiles exist on the same FQDN. |
| Authentication Method | `AAA Only` | Username + password forwarded to ISE via RADIUS. The point of having ISE is to use this path. |
| Authentication Server | `ISE-RADIUS` | The AAA group we built. Single dropdown wires the entire FTDv → ISE → Entra ROPC chain. |
| Authorization Server | `Use same authentication server` (default) | ISE handles both auth and authz in our policy set. Splitting them adds complexity for no demo value. |
| Accounting Server | `ISE-RADIUS` | Enables ISE Live Sessions and rich session telemetry in cdFMC dashboards. No extra ISE config required. |
| Client Address Assignment | ✅ Use IP Address Pools, point at `50_Net_Addr_Pool` | Range type object, value `192.168.50.1-192.168.50.25`. The pool is the IP space we hand to connecting clients. |
| Group Policy | `DfltGrpPolicy` | Default works for the demo. Customize later for split-tunnel, DNS, or banner if needed. |

**Why AAA Only and not SAML for RAVPN?**

The workshop demos two complementary auth architectures by design:

- **RAVPN** uses AAA Only → ISE → Entra ROPC → password only, no MFA.
- **ZTAA** uses SAML → Entra direct → MFA enforced.

The contrast is the lesson. ROPC (the protocol ISE uses to talk to Entra) cannot do MFA — that is a protocol-level limitation, not a configuration oversight. If we picked SAML for RAVPN, ISE would be bypassed entirely and both demos would look architecturally identical to the audience. The whole point of the workshop is showing two different trust models behind the same identity provider.

**Why enable accounting?**

Three small wins for zero ISE-side effort:

- ISE `Operations > RADIUS > Live Sessions` populates with active VPN sessions, which is great demo material — pivot to ISE during the demo and show the audience exactly who is connected right now.
- cdFMC's RAVPN dashboard fields that depend on accounting (geographic location, session uptime, byte counts) populate. The geolocation demo block in Phase 4 needs this telemetry.
- Production-shape config. Every real RAVPN deployment enables accounting. Skipping it is shortcut behavior that does not match what attendees would do at home.

The NAD record we built in ISE step 4 already covers accounting: ISE listens on UDP 1813 by default and uses the same shared secret as auth.

### Page 3: Secure Client Image

Pick the headend/webdeploy package or packages you uploaded. For a macOS-only test today, one is fine. For demo day with a mixed audience, upload both platforms before the demo.

### Page 4: Access & Certificate

Binds the connection profile to a specific FTDv interface and identity cert.

| Field | Value |
|---|---|
| Interface group / Security Zone | `outside` |
| FQDN of the device interface | `vpn.rooez.com` |
| Enable DTLS | ✅ |
| Enable Cisco Secure Client | ✅ |
| SSL Global Identity Certificate | `ravpn-identity` |
| IPsec IKEv2 Identity Certificate | (skip — IPsec is off) |
| Bypass Access Control policy for decrypted traffic | leave default (checked) |

`Bypass Access Control policy for decrypted traffic` (the cdFMC label for `sysopt connection permit-vpn`) tells FTDv to skip Access Control Policy enforcement for traffic that has already been decrypted from the VPN tunnel. This simplifies the demo — auth → tunnel → straight to inside without an extra ACP rule. In production you would typically uncheck this and write explicit ACP rules so VPN traffic is subject to the same controls as everything else.

### Page 5: Summary

Read-back of every choice. Click **Finish** to create the policy and address pool/group policy objects. Then click **Deploy** in the top-right banner to push the policy to `ftd-ravpn`.

First deploy of an RAVPN policy can take 5–10 minutes because cdFMC pushes the Secure Client image and cert configuration in addition to the connection profile.

## Network object planning for NAT

The wizard creates a Network object for the address pool automatically. For the NAT rule we add after deploy, we create a **separate** Network object on purpose.

### Two objects can have the same CIDR

cdFMC has no uniqueness constraint on the value of a Network object, only on the name. So this is allowed:

| Name | Type | Value | Used by |
|---|---|---|---|
| `branch-lan` | Network | `192.168.0.0/16` | Pre-existing ACL or routing rule unrelated to VPN |
| `vpn-pools-supernet` | Network | `192.168.0.0/16` | NAT rule for VPN client traffic |

Both objects exist independently. Each carries its own intent in its name. The NAT rule references `vpn-pools-supernet` regardless of what `branch-lan` is doing.

### Why not just reuse `branch-lan`?

Functionally identical at deploy time. Semantically a future bug.

- **Names lie about intent.** Six months from now someone reads "NAT source = branch-lan" and concludes "we are NATing branch traffic, why?" The name says branch, the rule means VPN.
- **Coupling.** If `branch-lan` ever changes because the actual branch network moves, the VPN NAT silently changes too. One object, two unrelated business meanings, one inevitable bug.
- **Audit posture.** Cisco best practice is one object per logical concern. A reviewer flags `branch-lan` showing up in a VPN-pool NAT rule as a misconfiguration even when it is not.

The right approach is two objects with the same CIDR but different names that describe their intent.

### Why a `/16` supernet instead of just the pool's `/24`

So that adding a second connection profile on demo day (with a new pool like `192.168.60.0/24`) requires zero NAT changes. The supernet `192.168.0.0/16` already covers any VPN pool we will create under `192.168.x.x`. One NAT rule, infinite pools.

The `/16` looks wide but is operationally safe because the NAT rule is scoped `outside → inside` — it only triggers on traffic that entered via the outside interface (decapsulated VPN) and is exiting via the inside interface. Random Internet traffic with `192.168.x.x` source IPs (which Azure already drops as bogon) cannot match.

### The two objects we will end up with

| Name | Type | Value | Purpose |
|---|---|---|---|
| `50_Net_Addr_Pool` | Range | `192.168.50.1-192.168.50.25` | Created by the wizard. Bound to the connection profile so Secure Client gets an IP from this range. |
| `vpn-pools-supernet` | Network | `192.168.0.0/16` | Created manually for the NAT rule. Covers all VPN pools we will ever add under `192.168.x.x`. |

Pool objects are **Range** type because they describe IPs to hand out, not subnets. NAT source objects are **Network** type because they describe subnets to match.

## Order of operations

1. Run the Remote Access VPN wizard. Creates the policy, the connection profile, the address pool object, the group policy, the first deployment.
2. Verify Secure Client connects and authenticates. **At this point the auth path through ISE → Entra works, but reaching the trading app fails** because no NAT rule exists yet. This is the expected interim state.
3. Add the NAT rule above. Deploy again.
4. Re-test. Now the tunnel completes end-to-end and the trading app loads.

We separate the two deployments deliberately to isolate failure modes. If after step 2 the auth path fails, the problem is RADIUS / ISE / Entra. If after step 2 the auth works but step 4 still cannot reach the app, the problem is NAT or routing. Splitting the deploys gives you that clarity.

## Network object you will create for the NAT rule

The wizard creates a Network object for the address pool automatically. If you want a separate object scoped to the entire `/24` (rather than the `.1-.50` range the pool object uses), create it manually:

**Objects > Object Management > Network > + Add Network**

| Field | Value |
|---|---|
| Name | `ravpn-pool-net` |
| Type | Network |
| Value | `192.168.50.0/24` |

Reference this object as the Original Source in the NAT rule. The wider `/24` makes the rule resilient if you expand the pool later — you do not have to update the NAT rule when you add more IPs to the pool range.

## Verify

After the second deployment (step 4 above):

- [ ] Secure Client connects to `vpn.rooez.com` as `trader1@rooez.com`. The session shows `Connected` and a pool IP from `192.168.50.0/24`.
- [ ] From the connected laptop: `curl -k https://10.100.3.20/` returns the trading app HTML, or a browser to the same URL renders the dashboard.
- [ ] In ISE Live Logs (`Operations > RADIUS > Live Logs`) the auth event shows `PermitAccess`.
- [ ] In cdFMC (`Analysis > Connections > Events`), you see VPN-pool traffic translated to `10.100.3.10` egressing to the trading app.
- [ ] Disconnecting Secure Client breaks reachability to `vpn.rooez.com/vpn` immediately — the dashboard requires the tunnel.

## Diagnostic commands on the FTD CLI

Useful CLI tools when something doesn't work as expected. SSH to FTD via Bastion (`scripts/bastion-tunnel.sh ftdv 50022`, then `ssh -p 50022 admin@127.0.0.1`) and you land at the FTD `>` prompt.

### Quick interface health check

```
> show interface ip brief
```

One-line-per-interface summary. Shows IP, status (administratively up vs down), and physical link state. The fastest way to confirm an interface deploy actually applied.

### MAC-to-Azure-NIC mapping

```
> show interface | include MAC|line protocol
```

Filters the verbose `show interface` output to only the interface header and MAC address lines. Cross-reference these MACs with Azure's view of the NICs:

```bash
az vm show -g rg-ravpn-demo -n vm-ftdv \
  --query "networkProfile.networkInterfaces[].id" -o tsv | \
  while read nic_id; do
    nic_name=$(echo "$nic_id" | awk -F/ '{print $NF}')
    mac=$(az network nic show --ids "$nic_id" --query "macAddress" -o tsv)
    echo "$nic_name: $mac"
  done
```

Azure formats MACs as `00-22-48-27-4D-3C`, FTD CLI uses `0022.4827.4d3c`. Same hex, different separators.

### L2 reachability

```
> show arp
```

If you see an ARP entry for the destination IP, L2 is working — the destination machine is alive on the subnet and FTD can address it directly. If ARP is empty, either the destination is down or there's an L2 issue.

### L3 reachability from FTD

```
> ping system <destination-ip>
```

Sources from FTD's data plane and sends ICMP. **Subject to the Access Control Policy** — if FTD has no permissive ACP rule, this fails with 100% packet loss even when the destination is alive. That doesn't mean the network is broken; it means FTD's ACP is denying FTD-origin traffic.

### Full firewall path trace

The most powerful diagnostic command on FTD:

```
> packet-tracer input <interface> <protocol> <src-ip> <src-port> <dst-ip> <dst-port>
```

Example for testing TCP-443 from FTD inside to the trading app:

```
> packet-tracer input inside tcp 10.100.3.10 12345 10.100.3.20 443
```

The output walks every phase the firewall would apply to a real packet: ACL check, route lookup, NAT translation, NSG rules, classify table, final action. Each phase shows ALLOW or DROP with the rule that decided. The final `Action: drop` or `Action: allow` is the verdict.

**Reading the output**:

- `Phase 1: ACCESS-LIST` — L2 access list (rarely the cause).
- `Phase 2: ROUTE-LOOKUP` — does FTD have a route to the destination? `Result: ALLOW` means yes.
- `Phase 3: OBJECT_GROUP_SEARCH` — NSG / object-group rules.
- `Phase 4: ACCESS-LIST` — Access Control Policy. If `Result: DROP` here, your ACP is denying the traffic.
- Final block — the decisive verdict, including the drop reason if anything failed.

This is the single most useful command for "why isn't this traffic working" questions. Faster than reading logs, more precise than ping.

### When ACP default-deny bites you

A fresh FTD has an empty Access Control Policy. The implicit rule at the bottom is `deny any any`. So:

- `ping system 10.100.3.20` from FTD: blocked by ACP.
- `curl https://10.100.3.20` from a VPN client *with sysopt-permit-vpn enabled*: allowed because VPN-decapsulated traffic bypasses ACP entirely.
- `curl https://10.100.3.20` from a VPN client *without sysopt-permit-vpn*: blocked by ACP unless you add an explicit permit rule.
- Trading app traffic during ZTAA (where FTD acts as a proxy, not VPN decap): blocked by ACP — needs explicit permit rules.

For the RAVPN demo, sysopt-permit-vpn (the "Bypass Access Control policy for decrypted traffic" checkbox on wizard Page 4) handles VPN traffic. FTD-origin tests like `ping system` will still fail until you add an ACP rule. That's a cosmetic issue for our demo, not a real one.

For ZTAA in Phase 5, you must add ACP rules permitting FTD's proxy traffic to reach the protected applications. Plan to build the ACP before starting that phase.

## When it gets stuck

- **Secure Client connects, auth succeeds, but inside resources are unreachable.** NAT rule missing or not deployed. Check `Policies > NAT` and confirm the rule exists, is enabled, and was included in the most recent deploy.
- **Secure Client connects but no pool IP is assigned.** Pool exhausted (rare with 50 IPs and one tester) or the pool object is not bound to the connection profile.
- **No RADIUS Live Log entry on auth attempt.** FTDv shared secret in cdFMC does not match ISE's NAD record. Both must be byte-for-byte identical.
- **Auth fails with `AAA failure`.** Check FTDv → ISE reachability. From the FTD CLI: `ping system 10.100.4.10`. Then `test aaa-server authentication ISE-RADIUS host 10.100.4.10 username trader1@rooez.com password '<pw>'`.
- **TLS error in Secure Client.** The identity cert was not pushed to FTDv, or the FQDN in Secure Client does not match a SAN on the cert. Our wildcard covers `*.rooez.com`, so any host under that domain works. Confirm in cdFMC `Devices > Certificates` that the `ravpn-identity` row shows the CA and ID indicators populated.
- **`test aaa-server` from FTD CLI returns `Authentication Server not responding: No active server found` even when routing is fine.** FTD's data plane needs a route to the AAA server. The default route added by `configure network management-data-interface` (during cdFMC registration) usually covers this — confirm with `show route` and look for `S* 0.0.0.0/0 [1/0] via 10.100.2.1, outside`. If routing checks out, the server may have been marked dead from prior failed attempts. Reset with `clear aaa-server statistics ISE-RADIUS` and retry.
- **ISE Live Logs show `5405 RADIUS Request dropped` and event details say "The 'Drop' advanced option is configured in case of a failed authentication request".** ISE intentionally suppressed the response. The REST ID Store's "Process failure" advanced setting defaults to **Drop**, which is hostile to debugging — FTD gets no reply and you have to dig in Live Logs to see what happened. **Change it to Reject**: `Administration > Identity Management > External Identity Sources > REST > ENTRA_ID > Advanced Settings > If process failure → Reject`. After this change, FTD gets a clean "Authentication Failed" response on real failures and you can troubleshoot from the FTD-side error message.
- **ISE Live Logs show `Username: USERNAME` instead of the real username when running `test aaa-server` from FTD CLI.** Known quirk of the FTD `test aaa-server` command on some builds — it sends a placeholder username instead of the one you typed, so the request always fails at Entra (the user "USERNAME" doesn't exist). This is harmless: the actual VPN connection from Secure Client sends the real username from the login dialog. Validate the auth path with a real Secure Client connection rather than relying on `test aaa-server`.
- **Bastion CLI tunnels disconnect the moment Secure Client connects.** Expected behavior with the default `Tunnel All Networks` group policy — once VPN comes up, every laptop destination routes through FTD, including the Azure CLI's tunnel to Bastion's public IP. Workarounds: (a) accept the trade-off and disconnect VPN when you need ISE GUI access via Bastion; (b) switch the group policy to **Split Tunnel** with include-only `10.100.0.0/16` so only VNet traffic goes through the tunnel and Bastion stays alive. For demo storytelling, Tunnel All looks more impressive on stage. For day-to-day testing, Split Tunnel is more convenient. Toggle in `Objects > Object Management > VPN > Group Policy > DfltGrpPolicy > General > Split Tunneling`.
