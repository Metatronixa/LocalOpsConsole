# LocalOpsConsole Roadmap

Public roadmap for the Windows Operations Platform. Dates are directional, not commitments.

## Shipped (v2.1 platform wave)

- Overview dashboard (health + security + incidents)
- Enterprise navigation (Operations, Security, Health, Inventory, Incidents, Monitoring, Automation, Settings)
- Event Intelligence wiring (watch → rules → correlation → incidents → notify → timeline)
- SecurityManager / IntegrityManager / PermissionManager execution gate
- Security Baseline module (score, compliance, recommendations)
- Module depth: Services, Network/Internet Health, Storage, Printers, Updates
- Fast Security Tools + Event Log views (bounded queries)
- Opt-in automation playbooks + Settings notification prefs UI
- Dark ops-center UI contrast pass
- Marketing website rebuild (static) + professional docs hub
- v2.1.1: Settings API fix, generic module views, fleet LAN URL hints, install docs

## Next

- Additional automation playbooks and safer verify/notify chains
- Richer Inventory and Reports sections
- More Security Baseline remediations (explicit, elevated, audited)
- Gallery screenshots for Overview / Incident Center / Security Baseline
- Expanded rule packs (network, storage, identity)

## Later

- Remote agent evolution (centralized management still opt-in)
- Signed module feeds / enterprise policy packs
- Multi-host Overview for fleet operators
- Commercial licensing pages (site ready; product remains MIT until decided)

## Principles

- Local-first and offline-capable remain non-negotiable
- No mandatory telemetry
- Privileged operations stay explicit and fail-safe
