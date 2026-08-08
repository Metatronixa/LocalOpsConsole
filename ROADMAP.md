# LocalOpsConsole Roadmap

Public roadmap for the Windows Operations Platform. Dates are directional, not commitments.

## Shipped (v2.2.0)

- Overview dashboard (health + security + incidents)
- Enterprise navigation (Operations, Security, Health, Inventory, Incidents, Monitoring, Automation, Settings)
- Event Intelligence (watch → rules → correlation → incidents → notify → timeline)
- **Threat Operations** (stream, filters, ScriptBlock decode, agent telemetry)
- SecurityManager / IntegrityManager / PermissionManager execution gate
- Security Baseline (This PC full audit; fleet agent audit from the same page)
- Module depth: Services, Network/Internet Health, Storage, Printers, Updates, Remote, Remote Support, SyncMe, Startup
- Infrastructure modules: Active Directory, DNS, DHCP, Group Policy, Hyper-V, Certificates, Server Operations
- Opt-in Automation Hub playbooks (local / fleet / both + Run now)
- Computers (fleet): enroll, drawer actions, self-update, policy packs, software catalog (winget / local HMAC / HTTPS)
- Network Map: gateway clusters, Map/List, Agents/LAN/Offline filters
- Headless launcher + UI Restart / Shutdown
- Dark ops-center UI; licensed marketing site + update feed on opsconsole.co.za (local tree, not on GitHub)

See also [docs/AGENT_ROADMAP.md](docs/AGENT_ROADMAP.md) for agent command detail.

## Next

- Richer Inventory and Reports sections
- More Security Baseline remediations (explicit, elevated, audited) from the baseline page where safe
- Agent Event Intelligence → scoped auto playbooks (Hub v2)
- Expanded rule packs (network, storage, identity)
- Deeper Threat Operations correlation into Incident Center

## Later

- Signed module feeds / richer enterprise policy packs
- Multi-select bulk fleet actions
- Self-serve licensing / purchase flow

## Principles

- Local-first and offline-capable remain non-negotiable
- No mandatory telemetry
- Privileged operations stay explicit and fail-safe
- Official builds are licensed commercially; source remains available for development
