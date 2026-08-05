# LocalOpsConsole User Guide

LocalOpsConsole is a **local-first Windows Operations Platform** for IT professionals, MSPs, system administrators, and power users.

It combines plugin diagnostics with **Event Intelligence** — continuous observation that surfaces **incidents**, not raw event noise.

## Launch

1. Run `start.bat` (UAC elevation recommended for remediations).
2. Open the URL printed in the console (default `http://localhost:8787/`).
3. You land on **Overview** — health score, security score, and active incidents.

## Platform navigation

| Section | Purpose |
|---------|---------|
| Overview | Is this computer healthy? |
| Operations | System tools, services, updates, network, printers, fleet, … |
| Security | Security Center, Security Baseline, Defender tools, Event Log |
| Health | Health Center checks |
| Performance | System telemetry-focused views |
| Inventory | Devices, users, graphics, storage surfaces |
| Incidents | Incident Center |
| Monitoring | Alerts + Timeline |
| Automation | Opt-in playbooks and history |
| Settings | Notification prefs, quiet hours, maintenance |

Profiles (Helpdesk, Desktop Support, …) still filter which modules appear.

## Event Intelligence

When `eventIntelEnabled` is true in `settings.json`:

- Watchers observe Event Logs and related signals
- Rules under `rules/` evaluate normalized events
- Correlation opens/updates **incidents**
- Notifications respect severity, channels, quiet hours, and maintenance mode
- Automation runs only when a rule sets `automation.enabled: true`

## Security Baseline

Open **Security Baseline** and run **Audit**. You get:

- Security Score
- Risk Rating
- Compliance counts
- Per-control Pass/Warning/Fail
- Recommendations

Audit is read-only. Remediation remains explicit elsewhere.

## Integrity

Module execution is gated:

1. Manifest validation  
2. SHA-256 integrity (warn in source; enforce in packaged builds)  
3. Elevation / permissions  
4. Dependencies  
5. Parameter allow-list  
6. Path jail  

Failures can open Security incidents.

## Modules — documentation template

Each module should document:

- **Purpose**
- **Capabilities** (inventory, diagnostics, monitoring, remediation, automation, reporting)
- **Diagnostics**
- **Remediation**
- **Automation**
- **Permissions**
- **Security implications**
- **Expected runtime**
- **Typical use cases**

See [docs/modules/](modules/) for filled examples.

## Security tools & Event Log

**Security** and **Event Log** use dedicated dashboard views that paint immediately, then load data asynchronously:

- Firewall / Defender status with short timeouts
- Event Log summary uses **capped samples** (never unbounded WinEvent scans)
- Recent errors are limited to a time window (default 48h) and max event count

Prefer **Security Center** / **Security Baseline** for posture scoring. Prefer **Timeline** / **Incidents** for Event Intelligence correlations.

## Updates

Use the in-app update banner or `GET /api/v1/updates/check`. Release checksums live in `website/uploads/update.json`.

## Fleet (optional)

LocalOps Agent can enroll with HMAC auth for heartbeat and command polling. Fleet is optional — the console remains useful fully offline. Leave `fleetEnrollToken` empty in committed settings; generate a token locally when enabling fleet.

### Install agent on another PC

1. On the **console** PC, set `bindHost` to `0.0.0.0` (or the LAN IP) so HttpListener accepts remote connections. Optionally set `fleetPublicUrl` to `http://<console-LAN-IP>:8787`.
2. Restart the console. Open **Computers** and copy the install one-liner.
3. On the **remote** PC, extract `LocalOpsAgent-x.y.z.zip` and run as Administrator:

```powershell
.\Install-LocalOpsAgent.ps1 -ServerUrl "http://192.168.1.10:8787" -EnrollToken "YOUR_TOKEN"
```

Use the console’s LAN IP (or `fleetPublicUrl`) — **not** `127.0.0.1` / `localhost`. Those only work on the console host itself. The Computers UI suggests the detected LAN IP when `fleetPublicUrl` is empty.

## Troubleshooting

- Check `logs/YYYY-MM-DD.log`
- Confirm the elevation badge for locked actions
- Use the live console stream for script errors
- Set `integrityMode` to `warn` during local module development
- If Security/Event Log feel stuck, hard-refresh the UI and confirm the server was restarted after pulling updates
- Event Log “Access denied” on the Security channel is normal without elevation
- Remote agents: use console LAN IP / `fleetPublicUrl` for `-ServerUrl`; set `bindHost` to `0.0.0.0`
