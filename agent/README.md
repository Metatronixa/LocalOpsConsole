# LocalOps Agent (v2.3.0)

Outbound Windows fleet agent for [LocalOpsConsole](https://github.com/Metatronixa/LocalOpsConsole). The agent initiates all traffic to the console — no inbound listener on managed PCs.

See [docs/AGENT_ROADMAP.md](../docs/AGENT_ROADMAP.md) for the V2 capability roadmap.

## Requirements

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1+
- Administrator rights for install
- Network reachability to the LocalOpsConsole server URL

## Install

1. Copy the `agent` folder (or extract a release zip) to the target PC.
2. On the console, open **Computers** and copy the enrollment token and install one-liner.
3. Run PowerShell **as Administrator**:

```powershell
.\Install-LocalOpsAgent.ps1 -ServerUrl "http://192.168.1.10:8787" -EnrollToken "YOUR_TOKEN_HERE"
```

The installer:

- Copies `LocalOpsAgent.ps1` to `C:\Program Files\LocalOpsAgent\`
- Writes config to `C:\ProgramData\LocalOpsAgent\config.json`
- Registers scheduled task **LocalOpsAgent** (SYSTEM, at startup)
- Starts the agent immediately

### Enrollment token model

- One **shared** enroll token for all new PCs (rotate in Computers → Enrollment if leaked).
- After enroll, each PC receives a unique **AgentId** + **AgentSecret** used for HMAC-signed API calls (including self-update). Day-to-day security is per-PC; the shared token is only for first join.

## Self-update (from console)

1. On the console, open **Computers → Enrollment** and click **Publish agent package** (copies `agent/LocalOpsAgent.ps1` into `data/fleet/agent-package/` with version + SHA-256).
2. Open a PC drawer → **Agent update** → **Update agent** (or Force update).
3. The agent downloads the package over HMAC, verifies SHA-256, replaces `Program Files\LocalOpsAgent\LocalOpsAgent.ps1`, and restarts the scheduled task.

**First upgrade from 2.1.x:** still manual (older agents do not understand `SelfUpdate`). After 2.2.0+, use the drawer.

## Remote agents and bindHost

By default the console binds to `localhost` (this PC only). Agents on other PCs need:

1. **A reachable ServerUrl** — LAN IP or **Tailscale IP** (e.g. `http://100.x.y.z:8787`), not `127.0.0.1` / `localhost`
2. **HttpListener open to the network** — set `bindHost` in `settings.json` to `0.0.0.0` (preferred; maps to all interfaces)

Optional: set `fleetPublicUrl` (e.g. `http://192.168.1.10:8787` or Tailscale) to pin the dashboard install one-liner. If unset, Computers uses the detected LAN IPv4 for the suggested `-ServerUrl`. Avoid binding HttpListener to a single LAN IP unless required — that can conflict with HTTP.sys URL reservations.

## Computers drawer (remote actions)

Open **Computers**, click a PC row — a side drawer shows live telemetry and grouped actions:

- **Agent update** — Update / force-update from published console package (2.2.0+)
- **Spike forensics** — High CPU/RAM (≥90%) queues `GetResourceOffenders`; drawer shows top process/service with End / Restart service; console Alerts + NotificationManager notify the admin; table shows a SPIKE cue
- **Network** — Flush DNS, Net smoke (ping + download + upload), Ping PC (console→agent latency)
- **Windows Update** — Check pending status; install pending updates (no KB uninstall yet)
- **Remote Support** — RustDesk status; silent install (requires `rustDeskInstallerUrl` HTTPS in settings)
- **Software** — Install from catalog (Computers → Manage software catalog): winget preferred, then local installers under `data/fleet/software/{id}/` (HMAC download), else HTTPS URL; opens `ProgramData\LocalOpsAgent\installs\{id}\`
- **Event Log** — Tail System / Application / Security
- **Services / Print** — Restart Spooler, Get Services, Restart Service
- **Inventory / Inspect** — Collect Inventory, Processes (End), Printers, Run Script
- **Message** — Message user on the remote PC
- **Repair** — SFC scan, CHKDSK scan (read-only), CHKDSK schedule `/F` (no auto-reboot)
- **Danger** — Restart Computer (60s delay), Remove agent

## Behavior

- Heartbeat every **30 seconds** (CPU, RAM, disk, network, uptime, etc.)
- Poll for commands every **3 seconds**
- HMAC-SHA256 signed requests after enrollment
- Logs: `C:\ProgramData\LocalOpsAgent\logs\agent-YYYY-MM-dd.log`

## Uninstall

```powershell
.\Uninstall-LocalOpsAgent.ps1
```

## Manual enrollment (advanced)

If config has `ServerUrl` and `EnrollToken` but no `AgentId`, the agent enrolls on first run. You can also set environment variables:

```powershell
$env:LOCALOPS_SERVER_URL = "http://192.168.1.10:8787"
$env:LOCALOPS_ENROLL_TOKEN = "token"
powershell -File LocalOpsAgent.ps1
```
