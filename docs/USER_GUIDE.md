# LocalOpsConsole User Guide

LocalOpsConsole is a **local-first Windows Operations Platform** (v2.2.0) for IT professionals, MSPs, system administrators, and power users.

**Official builds are licensed commercially.** Obtain access at [Get Access](https://www.opsconsole.co.za/get-access.html).

**Preferred reading:** the styled HTML guide (same content, full walkthrough):

- In the running app: open **Help** in the header, or browse `http://localhost:8787/user-guide.html`
- On the website: [User Guide](https://www.opsconsole.co.za/docs/user-guide.html)
- Packaged copy: `dashboard/user-guide.html`

This markdown file is a short companion for the repo. The HTML guide explains every major surface in detail.

## Launch

1. Extract a licensed build (or clone source for development).
2. Run `start.bat` (UAC once). The launcher is **headless** — no leftover console on success; the browser opens automatically.
3. Optional: `start-silent.vbs` for shortcuts / Startup folder; `start.ps1 -ShowConsole` for visible progress.
4. You land on **Overview** — health score, security score, and active incidents.
5. Use header **Restart** (headless relaunch, reconnect) or **Shutdown** (stop server). There is no Ctrl+C console after a successful start.

If the UI shows **Failed to fetch** for every API call, the server process is not running — use `start.bat` or Restart.

## Platform navigation

| Section | Purpose |
|---------|---------|
| Overview | Is this computer healthy? |
| Operations | System tools, services, updates, network, printers, fleet, SyncMe, Network Map, infra modules, … |
| Security | Security Center, Security Baseline, Threat Operations, Defender tools, Event Log |
| Health | Health Center checks |
| Performance | System telemetry-focused views |
| Inventory | Devices, users, graphics, storage, startup, power |
| Incidents | Incident Center |
| Monitoring | Alerts + Timeline |
| Automation | Opt-in playbooks (UI toggles) and history |
| Settings | Notification prefs, quiet hours, maintenance |

Profiles (Helpdesk, Desktop Support, …) still filter which modules appear.

## Threat Operations

**Security → Threat Operations**: live security stream, filters, ScriptBlock decode, agent telemetry ingest. See [docs/modules/ThreatOperations.md](modules/ThreatOperations.md).

## Event Intelligence

When `eventIntelEnabled` is true in `settings.json`:

- Watchers observe Event Logs and related signals
- Rules under `rules/` evaluate normalized events
- Correlation opens/updates **incidents**
- Notifications respect severity, channels, quiet hours, and maintenance mode
- Automation runs only when you enable the playbook on the **Automation** page (toggles apply immediately; prefs stored under `data/automation/`)

### Automation playbooks

Built-in pack (all default **off**; enable per rule on the Automation page):

| Playbook | Action | Risk |
|----------|--------|------|
| Spooler crash (7031 / 7034) | Restart Spooler → verify → close | Careful |
| Low disk | Temp cleanup | Safe |
| Monitored service down | Restart service | Careful |
| Printer offline | Clear print queue | Careful |
| Network down | DNS flush + DHCP renew | Careful |
| Update failed | Restart wuauserv / BITS | Careful |
| Event Log health | Timeline ack only | Notify |
| Defender / firewall disabled | Timeline ack only | Notify |
| Unexpected reboot | Timeline ack only | Notify |
| High CPU | Process snapshot | Safe |

**Risk meanings:** Safe = observe/cleanup · Careful = may restart services, clear jobs, or briefly disrupt network · Notify = timeline only (no remediation). Authors can add more under `rules/custom/`.

### Central hub (This PC + fleet)

On **Automation**, each playbook has:

- **Enable** — opt-in (still required for Event Intel auto on This PC)
- **Scope** — This PC / Fleet / Both (prefs under `data/automation/playbook-prefs.json`)
- **Fleet agents** — optional multi-select (empty = all **online** agents)
- **Run now** — runs the mapped action on scoped targets immediately (sticky status on the page)

Fleet remediations queue agent commands (`RestartSpooler`, `DiskCleanup`, `ClearPrintQueue`, `NetworkSoftRepair`, `RestartUpdateStack`, `CaptureProcessSnapshot`, …). Agents need **2.3.0+** with an updated script (Publish + Update agent).

**Auto today:** Event Intelligence still remediates **This PC only** when scope includes local. High CPU fleet spikes can auto-queue `CaptureProcessSnapshot` when the `high-cpu` playbook is enabled with Fleet/Both scope. **Hub v2** will add agent Event Log signals so Spooler/network playbooks can auto-target the right PC.

PowerShell Script Block Logging (Event ID **4104**) may appear when the console starts `api\server.ps1` — that is Windows logging the host process, not necessarily an attack.

## Fleet, Network Map, SyncMe, Settings

See the HTML user guide sections for Computers (fleet), Network Map, SyncMe, Settings keys, updates, access/elevation, and troubleshooting. Licensed operators get packages and update feeds through the Get Access channel — not public free downloads.
