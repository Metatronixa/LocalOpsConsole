# LocalOpsConsole User Guide

LocalOpsConsole is a **local-first Windows Operations Platform** (v2.1.8) for IT professionals, MSPs, system administrators, and power users.

**Preferred reading:** the styled HTML guide (same content, full walkthrough):

- In the running app: open **Help** in the header, or browse `http://localhost:8787/user-guide.html`
- On the website: [User Guide](https://www.opsconsole.co.za/docs/user-guide.html)
- Packaged copy: `dashboard/user-guide.html`

This markdown file is a short companion for the repo. The HTML guide explains every major surface in detail.

## Launch

1. Run `start.bat` (UAC elevation recommended for remediations).
2. Open the URL printed in the console (default `http://localhost:8787/` on **this** PC).
3. You land on **Overview** — health score, security score, and active incidents.

If the UI shows **Failed to fetch** for every API call, the server process is not running — start it again with `start.bat`.

## Platform navigation

| Section | Purpose |
|---------|---------|
| Overview | Is this computer healthy? |
| Operations | System tools, services, updates, network, printers, fleet, SyncMe, Network Map, … |
| Security | Security Center, Security Baseline, Defender tools, Event Log |
| Health | Health Center checks |
| Performance | System telemetry-focused views |
| Inventory | Devices, users, graphics, storage, startup, power |
| Incidents | Incident Center |
| Monitoring | Alerts + Timeline |
| Automation | Opt-in playbooks (UI toggles) and history |
| Settings | Notification prefs, quiet hours, maintenance |

Profiles (Helpdesk, Desktop Support, …) still filter which modules appear.

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

## Security Baseline

Open **Security Baseline**. Pick **This PC** or an enrolled fleet agent, then **Run Audit**. You get score, risk rating, compliance counts, per-control results, and recommendations. Audit is read-only.

- **This PC** uses the full Security Baseline module diagnostics.
- **Fleet** queues `AuditSecurityBaseline` (agent **2.2.0+**; richer BitLocker/TPM/Secure Boot checks need the current agent script). Status stays on this page while the command runs.
- **Apply hardening-basic** (firewall + Defender realtime) remains on **Computers → Policy** with an explicit confirm.

You can open the page with an agent preselected from the Computers drawer (**Open Security Baseline**).

## Integrity

Module execution is gated:

1. Manifest validation  
2. SHA-256 integrity (warn in source; enforce in packaged builds)  
3. Elevation / permissions  
4. Dependencies  
5. Parameter allow-list  
6. Path jail  

## Modules — documentation template

Purpose · Capabilities · Diagnostics · Remediation · Automation · Permissions · Security implications · Expected runtime · Typical use cases.

See [docs/modules/](modules/) for filled examples.

## Security tools & Event Log

Dedicated dashboard views paint immediately, then load data asynchronously with **bounded** WinEvent queries. Prefer Security Center / Baseline for posture; Timeline / Incidents for correlations.

## Updates

Use the in-app update banner or `GET /api/v1/updates/check`. The app checks `https://www.opsconsole.co.za/uploads/update.json` by default (override with `updateUrl` in `settings.json`). Checksums are SHA-256 in that manifest.

## Fleet (optional)

LocalOps Agent enrolls with HMAC auth for heartbeat and command polling. Fleet is optional — the console remains useful fully offline. Leave `fleetEnrollToken` empty in committed settings; generate a token locally when enabling fleet.

### Install agent on another PC

1. On the **console** PC, set `bindHost` to `0.0.0.0` (listens on all interfaces; mapped to HttpListener `+`). Set `fleetPublicUrl` to `http://<console-LAN-IP>:8787` so agents get a reachable URL. Prefer this over binding HttpListener to a single LAN IP (can conflict with HTTP.sys reservations).
2. Restart the console. Open **Computers** and copy the install one-liner.
3. On the **remote** PC, extract `LocalOpsAgent-x.y.z.zip` and run as Administrator:

```powershell
.\Install-LocalOpsAgent.ps1 -ServerUrl "http://192.168.1.10:8787" -EnrollToken "YOUR_TOKEN"
```

Use the console’s LAN IP, **Tailscale IP**, or `fleetPublicUrl` — **not** `127.0.0.1` / `localhost`.

### Remote actions (Computers)

Select an online PC → detail panel: Flush DNS, Restart Spooler, Inventory, Processes (End), Printers, **Startup apps** (opens Inventory → Startup with that PC selected), Ping PC, Net smoke, Message, SFC, CHKDSK, Policy (audit / apply hardening-basic), Windows Update, RustDesk, software catalog, event log tails, agent self-update, and more. Use **Network Map** under Operations for agents + LAN neighbors in **gateway clusters** (not a fixed star). Switch to **List** when the LAN is crowded; filter Agents / LAN / Offline on either view.

### Software catalog (winget / local / URL)

On **Computers → Manage software catalog**:

1. **Winget** — Id + WingetId (e.g. `RARLab.WinRAR`).  
2. **Local** — Copy the installer into `data/fleet/software/{Id}/` on the console host, then **Register** with FileName + SilentArgs. The console stores SHA-256. Agents download over the same HMAC-signed fleet API as self-update (works with LAN `http://` `ServerUrl`). You own SilentArgs (no auto-detect).  
3. **URL** — HTTPS installer URL; optional Sha256.

Install from a PC drawer → Software. Prefer order: **winget → local → HTTPS**. Local installs need agent **2.3.0+** (Publish + Update agent). Catalog delete removes the entry only (files stay unless you delete the folder).

### Startup (This PC or fleet)

**Inventory → Startup** can target **This PC** or an enrolled fleet agent. Remote **Startup apps** / **Scheduled tasks** queue `GetStartupApps` / `GetScheduledTasks` and show a sticky Pending/Running chip above the results (no need to scroll Computers command history). Remediation (`SetStartupEnabled`) remains This PC only. Agents need **2.3.0+** with the updated script (Publish + Update agent, or reinstall).

Click a **Command history** row to open its result in the **Command result** panel (no scrolling required). If one command stays **Running**, newer work stays **Pending** until it finishes, times out (45 minutes), or you click **Clear stuck**.

## SyncMe

Set `syncMePath` (or register via the SyncMe module). Open **Operations → SyncMe** for status, console, download page, and backup actions.

## Troubleshooting

- Check `logs/YYYY-MM-DD.log`
- Confirm the elevation badge for locked actions
- Use the live console stream for script errors
- Set `integrityMode` to `warn` during local module development
- Run `.\tools\smoke-api.ps1` with the server running
- Remote agents: `fleetPublicUrl` (LAN or Tailscale IP) + `bindHost: 0.0.0.0`; if start fails with “conflicts with an existing registration”, free port 8787 / check `netsh http show urlacl`
- Commands stuck **Pending**: often a stuck **Running** command is blocking the queue (see Command history). Use **Clear stuck**, or wait for short-command (5m) / long-command (45m) Running timeout. Pending never claimed fails after ~10m. Restart task **LocalOpsAgent**, check `C:\ProgramData\LocalOpsAgent\logs` for Poll errors, confirm `ServerUrl`. **Failed** with “Unknown command type” or disabled Event Log/WU buttons means an old agent — install Agent **2.3.0+** (2.1.5 cannot self-update; reinstall manually)
- Event Log “Access denied” on the Security channel is normal without elevation

See also the [HTML User Guide](https://www.opsconsole.co.za/docs/user-guide.html), `CHANGELOG.md`, and `SECURITY.md`.
