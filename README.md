# LocalOpsConsole

[![License: MIT](https://img.shields.io/badge/License-MIT-0f766e?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Metatronixa/LocalOpsConsole?color=14b8a6&style=flat-square&label=release)](https://github.com/Metatronixa/LocalOpsConsole/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D4?style=flat-square&logo=windows&logoColor=white)](https://github.com/Metatronixa/LocalOpsConsole)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=flat-square&logo=powershell&logoColor=white)](https://github.com/Metatronixa/LocalOpsConsole)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-059669?style=flat-square)](CONTRIBUTING.md)

**Local-first Windows Operations Platform** (v2.1.6) for IT professionals, MSPs, and power users — diagnostics, Event Intelligence, incidents, security baseline, and safe remediation.

PowerShell HttpListener API + offline SPA. Plugin modules via `module.json`. **Overview** answers “Is this computer healthy?” using health score, security posture, and active incidents — not raw Event Viewer dumps.

<p align="center">
  <img src="https://www.opsconsole.co.za/assets/img/screenshot-overview.png" alt="LocalOpsConsole — Overview health, security, and incidents" width="860" />
</p>
<p align="center"><em>Overview — health score, security posture, and active incidents</em></p>

<p align="center">
  <img src="https://www.opsconsole.co.za/assets/img/screenshots/security-center.png" alt="LocalOpsConsole — Security Center" width="860" />
</p>
<p align="center"><em>Security Center — posture score and control status</em></p>

<p align="center">
  <img src="https://www.opsconsole.co.za/assets/img/screenshot-system.png" alt="LocalOpsConsole — live system telemetry" width="860" />
</p>
<p align="center"><em>Live telemetry — CPU, RAM, disk, network, GPU</em></p>

<p align="center"><a href="https://www.opsconsole.co.za/screenshots.html">More screenshots by category →</a></p>

## Why free?

Intentionally MIT so techs and small teams can operate Windows endpoints without buying another cloud agent. Use it, fork it, improve it. The architecture is ready for future commercial offerings without abandoning local-first defaults.

## Quick start

### Option A — Download a release

1. Grab the latest ZIP from [GitHub Releases](https://github.com/Metatronixa/LocalOpsConsole/releases/latest).
2. Extract to a writable folder.
3. Double-click **`start.bat`** (requests UAC so remediations work).

### Option B — Bootstrap script

```powershell
iwr https://raw.githubusercontent.com/Metatronixa/LocalOpsConsole/main/scripts/Install-LocalOpsConsole.ps1 -OutFile "$env:TEMP\Install-LOC.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\Install-LOC.ps1" -Launch
```

### Option C — From source

```powershell
git clone https://github.com/Metatronixa/LocalOpsConsole.git
cd LocalOpsConsole
.\start.bat
```

Opens `http://localhost:8787/` on **Overview**.

## Features

| Area | What you get |
|------|----------------|
| **Overview** | Health + security scores and active incidents at a glance |
| **Event Intelligence** | Watchers, JSON rules, correlation, incidents, notifications, timeline |
| **Security Baseline** | Defender, Firewall, BitLocker, TPM, Secure Boot, UAC, SMBv1, RDP, WinRM, logging, … |
| **Integrity gate** | Manifest + SHA-256 + elevation + path jail before module execution |
| **Automation** | Opt-in playbooks (restart → verify → notify → close) |
| **Computers (fleet)** | Optional LocalOps Agent — heartbeat, commands, scripts, repair |
| **Network Map** | Spatial view of agents + LAN neighbors |
| **Internet Health** | DNS, latency, connectivity, repairs |
| **Services / Storage / Printers / Updates** | Inventory, monitoring, remediation, reporting |
| **Access** | Standard users: diagnostics · Elevated: remediations |

## Documentation

| Doc | Description |
|-----|-------------|
| [User Guide (HTML)](https://www.opsconsole.co.za/docs/user-guide.html) | Complete operator walkthrough (also in-app via **Help** → `/user-guide.html`) |
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | Markdown companion |
| [Docs site](https://www.opsconsole.co.za/docs/) | Installation, architecture, modules, API, FAQ |
| [docs/modules/](docs/modules/) | Per-module docs |
| [ROADMAP.md](ROADMAP.md) | Public roadmap |
| [SECURITY.md](SECURITY.md) | Security policy |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |
| [LICENSE](LICENSE) | MIT |

## Architecture

- `api/` — HttpListener + thin `/api/v1` router
- `core/` — Engine bootstrap, Security/Integrity/Permission managers, Event Intelligence, Fleet, ModuleLoader, TaskRunner
- `rules/` — detection + optional automation JSON
- `modules/` — plugin packs (`module.json` + diagnostics/actions)
- `dashboard/` — offline SPA (Overview, Incidents, Security Center, …)
- `notifications/` — channel plugins
- `website/` — local marketing site + update feed (not tracked on GitHub; hosted at opsconsole.co.za)
- `data/integrity/` — module hash store (generated on build)

## API (summary)

`GET /api/v1/health` · `modules` · `telemetry` · `settings` · `integrity/status` · `automation/status` · `incidents` · `alerts` · `health-score` · `security-score` · `{module}/diagnostics|actions/{name}` · `fleet/*`

## Build

```powershell
.\build.ps1                 # dist ZIP + integrity hashes (enforce in package)
.\build.ps1 -PublishWebsite # also refresh website/uploads
```

## Safety

Privileged actions are listed in each module’s `requiresAdmin`. Automation is off unless a rule enables it. Packaged builds enforce module integrity; source defaults to `integrityMode: warn`.

- Binds to **localhost** only by default.
- Admin-required actions are blocked without elevation.
- UI works offline (no CDN).
- Do not expose the API to the public internet. For LAN fleet agents, set `bindHost` to `0.0.0.0` and use the console LAN IP (see the [User Guide](https://www.opsconsole.co.za/docs/user-guide.html)).
- See `SECURITY.md` and `CHANGELOG.md`.

## Updates

Default `updateUrl` is `https://www.opsconsole.co.za/uploads/update.json`. Override in `settings.json` if you host your own feed. Updates are never silent — the operator must confirm.

Bump SemVer in `VERSION`, then build. Attach the ZIP to a GitHub Release for public downloads.

```powershell
.\tools\smoke-api.ps1   # after start.bat — API smoke test
```

## License

MIT — Copyright 2026 Bradford Lotriet. Free for personal and commercial use.
