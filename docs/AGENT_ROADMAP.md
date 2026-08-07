# LocalOps Agent Roadmap (V2)

V2 is the product. Fleet agents enroll outbound to the console; remote ops live in the **Computers** side drawer.

## Shipped (Agent Ops Wave + Self-Update)

| Area | Capability |
|------|------------|
| Splash | Branded ~5s boot overlay while the console loads |
| Network | Flush DNS, net smoke (ping + download + upload Mbps), console→agent latency |
| Windows Update | Status (pending list) + install pending updates |
| RustDesk | Status + silent install (HTTPS URL from `settings.json`) |
| Software | Curated catalog (`data/fleet/packages.json`) + `InstallPackage` (winget or HTTPS URL/MSI); opens `ProgramData\LocalOpsAgent\installs\{id}\` |
| Event Log | Tail System / Application / Security |
| Spike forensics | CPU/RAM ≥90% → `GetResourceOffenders` → Alerts inbox + NotificationManager + table SPIKE cue |
| Agent self-update | Publish package from console `agent/`; drawer **Update agent** (`SelfUpdate`) over HMAC + SHA-256 |
| Repair | SFC, CHKDSK scan, CHKDSK schedule `/F` |
| Inventory | Collect inventory, processes (end), printers, services, scripts, message user |
| Queue UX | Click command history → result panel; Clear stuck; Running auto-timeout 45m |
| Network Map | Separate dash: agents + LAN discovery by gateway (`GET /fleet/topology`) |
| Policy | `AuditSecurityBaseline` + `ApplySecurityPolicy` (`hardening-basic`: firewall + Defender realtime). Wallpaper lockdown deferred |

## Enrollment security

- **Shared enroll token** (`fleetEnrollToken`) for new installs — rotatable in Computers → Enrollment.
- **Per-PC AgentId + AgentSecret** after enroll — HMAC auth for heartbeats/commands/self-update.
- One-time per-PC enroll tokens remain optional future work (reduces risk if the shared token leaks).

## Next waves (planned)

### Queue & safety

- Command-queue approval for dangerous ops
- Soft vs forced reboot templates
- Whitelist + richer audit UI
- Optional one-time per-PC enroll tokens

### Playbooks & inventory

- Playbooks-on-PC (agent-side runbooks)
- Fuller structured inventory summary
- Clear Temp / Reset Network Stack one-clicks
- Multi-select bulk fleet actions (including bulk self-update)

### Clients & hooks

- Policy packs beyond hardening-basic (user-lockdown / wallpaper deferred); notification / health / update clients
- SyncMe hooks; richer RustDesk; later RDP hooks
- Website-driven file transfer to agents

### Observability

- Configurable spike thresholds
- CPU/RAM sparklines from heartbeat history
- Overview fleet health tile
- Disk-by-volume, startup/tasks summary

## Out of scope (for now)

- Uninstall Windows Update by KB
- Full Event Viewer (tail only)
- Browser upload of arbitrary EXE
- Auto-kill without confirm
- Auto self-update without confirm
- Full RMM feature chase
- Wallpaper / theme lockdown packs

## Version note

Current agent **2.3.0+** adds remote policy audit/apply. Self-update works from **2.2.0+**. Pre-2.2.0 agents need **one manual install**, then later upgrades use Computers → Update agent after **Publish agent package**.
