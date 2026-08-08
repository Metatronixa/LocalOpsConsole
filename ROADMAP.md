# LocalOpsConsole Roadmap

Public roadmap for the Windows Operations Platform. Dates are directional, not commitments.

## Shipped (v2.2.0)

- Overview dashboard (health + security + incidents)
- Enterprise navigation (Operations, Security, Health, Inventory, Incidents, Monitoring, Automation, Settings)
- Event Intelligence (watch â†’ rules â†’ correlation â†’ incidents â†’ notify â†’ timeline)
- **Threat Operations** (stream, filters, ScriptBlock decode, agent telemetry)
- SecurityManager / IntegrityManager / PermissionManager execution gate
- Security Baseline (This PC full audit; fleet agent audit from the same page)
- Module depth: Services, Network/Internet Health, Storage, Printers, Updates, Remote, Remote Support, SyncMe, Startup
- Infrastructure modules: Active Directory, DNS, DHCP, Group Policy, Hyper-V, Certificates, Server Operations
- Opt-in Automation Hub playbooks (local / fleet / both + Run now)
- Computers (fleet): enroll, drawer actions, self-update, policy packs, software catalog (winget / local HMAC / HTTPS)
- Network Map: gateway clusters, Map/List, Agents/LAN/Offline filters
- Hidden-window launcher + UI Restart / Shutdown (`start.bat` / `start.ps1`; not the same as appliance/API-only)
- License + product-mode architecture hooks (Community ungated; `GET /api/v1/license`; `-NoBrowser` / `-Appliance`)
- Dark ops-center UI; marketing site + update feed on opsconsole.co.za (local tree, not on GitHub)

See also [docs/AGENT_ROADMAP.md](docs/AGENT_ROADMAP.md) for agent command detail.

## Next

- Richer Inventory and Reports sections
- More Security Baseline remediations (explicit, elevated, audited) from the baseline page where safe
- Agent Event Intelligence â†’ scoped auto playbooks (Hub v2)
- Expanded rule packs (network, storage, identity)
- Deeper Threat Operations correlation into Incident Center

## Later

- Signed module feeds / richer enterprise policy packs
- Multi-select bulk fleet actions
- Offline signed license keys (Ed25519) with hard gate in a **paid Console / Appliance fork** (public tree stays Community ungated)
- Appliance package: API/fleet brain without dashboard; Scheduled Task / service host for `api\server.ps1`
- Self-serve licensing / purchase flow (site)

## Principles

- Local-first and offline-capable remain non-negotiable
- No mandatory telemetry
- Privileged operations stay explicit and fail-safe
- Public GitHub tree remains MIT Community (ungated); commercial SKUs live in a paid fork
- **All scripts are security-scanned always** before merge/release: PowerShell via PSScriptAnalyzer (`tools/Invoke-ScriptAnalyzerScan.ps1`); supported languages (JS/TS/etc.) via Snyk Code. Fix findings before shipping.
- Official commercial builds may be licensed; source on GitHub stays available for development
