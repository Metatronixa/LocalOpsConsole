# LocalOpsConsole

[![License: MIT](https://img.shields.io/badge/License-MIT-0f766e?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D4?style=flat-square&logo=windows&logoColor=white)](https://github.com/Metatronixa/LocalOpsConsole)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=flat-square&logo=powershell&logoColor=white)](https://github.com/Metatronixa/LocalOpsConsole)

**Local-first Windows Operations Platform** (v2.2.0) for IT professionals, MSPs, and power users — diagnostics, Event Intelligence, Threat Operations, incidents, security baseline, fleet agent, and safe remediation.

PowerShell HttpListener API + offline SPA. Plugin modules via `module.json`. **Overview** answers “Is this computer healthy?” using health score, security posture, and active incidents — not raw Event Viewer dumps.

Official builds are **licensed commercial distribution**. Source on GitHub is for development and review; obtain a license and package via [Get Access](https://www.opsconsole.co.za/get-access.html).

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

<p align="center"><a href="https://www.opsconsole.co.za/screenshots.html">More screenshots by category →</a> · <a href="https://www.opsconsole.co.za/get-access.html">Get Access →</a></p>

## Get Access

LocalOpsConsole is a **paid product**. Contact [bradford.lotriet@gmail.com](mailto:bradford.lotriet@gmail.com) or visit [Get Access](https://www.opsconsole.co.za/get-access.html) for licensing and delivery of official builds.

Developers contributing or reviewing the codebase:

```powershell
git clone https://github.com/Metatronixa/LocalOpsConsole.git
cd LocalOpsConsole
.\start.bat
```

Accept UAC once. The launcher starts **headless** (no leftover console); the browser opens `http://localhost:8787/` on **Overview**. Use **Restart** / **Shutdown** in the UI to control the server.

## Features

| Area | What you get |
|------|----------------|
| **Overview** | Health + security scores and active incidents at a glance |
| **Event Intelligence** | Watchers, JSON rules, correlation, incidents, notifications, timeline |
| **Threat Operations** | Security event stream, filters, ScriptBlock decode, agent telemetry |
| **Security Baseline** | Defender, Firewall, BitLocker, TPM, Secure Boot, … on This PC or a fleet agent |
| **Integrity gate** | Manifest + SHA-256 + elevation + path jail before module execution |
| **Automation** | Opt-in Hub playbooks (local / fleet / both + Run now) |
| **Computers (fleet)** | Optional LocalOps Agent — heartbeat, commands, scripts, repair, self-update |
| **Software catalog** | Winget, local installers on the console disk (HMAC download), or HTTPS URL |
| **Network Map** | Gateway clusters of agents + LAN neighbors; Map or List |
| **Infrastructure modules** | Active Directory, DNS, DHCP, Group Policy, Hyper-V, Certificates, Server Operations |
| **Internet Health** | DNS, latency, connectivity, repairs |
| **Services / Storage / Printers / Updates** | Inventory, monitoring, remediation, reporting |
| **Headless ops** | Hidden launcher; UI Restart (no second UAC) and Shutdown |
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
| [LICENSE](LICENSE) | MIT (source); official builds are licensed commercially |

## Architecture

- `api/` — HttpListener + thin `/api/v1` router
- `core/` — Engine bootstrap, Security/Integrity/Permission managers, Event Intelligence, Threat telemetry, Fleet, ModuleLoader, TaskRunner
- `rules/` — detection + optional automation JSON
- `modules/` — plugin packs (`module.json` + diagnostics/actions)
- `dashboard/` — offline SPA (Overview, Incidents, Security Center, Threat Operations, …)
- `notifications/` — channel plugins
- `website/` — local marketing site + update feed (not tracked on GitHub; hosted at opsconsole.co.za)
- `data/integrity/` — module hash store (generated on build)

## API (summary)

`GET /api/v1/health` · `modules` · `telemetry` · `settings` · `integrity/status` · `automation/status` · `incidents` · `alerts` · `health-score` · `security-score` · `{module}/diagnostics|actions/{name}` · `fleet/*` · `POST /shutdown` · `POST /restart`

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

Licensed operators receive builds through the update feed (`updateUrl`, default `https://www.opsconsole.co.za/uploads/update.json`). Updates are never silent — the operator must confirm.

Bump SemVer in `VERSION`, then build and publish the licensed package / feed.

```powershell
.\tools\smoke-api.ps1   # after start.bat — API smoke test
```

## License

Source repository: MIT — Copyright 2026 Bradford Lotriet.  
**Official product builds and support are licensed commercially** — see [Get Access](https://www.opsconsole.co.za/get-access.html).
