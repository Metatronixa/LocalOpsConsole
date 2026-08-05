# LocalOpsConsole User Guide

**Free and open source** (MIT) modular Windows diagnostic platform: PowerShell HttpListener API + offline SPA dashboard (**v1.3.0**).

Source and releases: [github.com/Metatronixa/LocalOpsConsole](https://github.com/Metatronixa/LocalOpsConsole)

## Getting started

1. Download `LocalOpsConsole-x.y.z.zip` from [Releases](https://github.com/Metatronixa/LocalOpsConsole/releases/latest), or use the bootstrap script on the [Download](../website/download.html) page, or clone the repo and run from source.
2. Extract to a writable folder (if using the ZIP).
3. Double-click **`start.bat`** (not `start.ps1` — Windows may open scripts in Notepad). The launcher requests UAC elevation by default.
4. Opens `http://localhost:8787/` (see `settings.json` → `port`).

### Standard user vs elevated

| Mode | What works |
|------|------------|
| **STANDARD USER** | Navigate all modules, live telemetry (incl. IPv6 / VPN chip when connected), most diagnostics (status, ping, hosts *read*, WINS/nbtstat, printer list/queue/events, RustDesk status/ID copy, Configuration HKCU settings, etc.) |
| **ELEVATED** | Remediations: spooler restart, clear/cancel jobs, hosts add/remove/toggle, RouteAdd, SFC/DISM, Security/Power policy, RustDesk install/service control, silent installs |

The header badge shows elevation state. Admin-only actions are disabled with a **Needs elevation** hint and return Access Denied without UAC. Cancel UAC on launch to stay as standard user — the app remains fully navigable.

### Shutdown

Use the header **Shutdown** button to stop the API server. The launcher (`start.bat` / `start.ps1`) exits when the server process ends.

### UI tour

- **Header** — version, elevation badge, CPU/RAM telemetry
- **Profile selector** — choose an operator profile (UI-only filtering)
- **Sidebar** — modules from `/api/v1/modules`
- **Main pane** — diagnostics and actions; results render as tables/cards when possible
- **Live console** — execution stream (also written under `logs/`)

### Diagnostics vs actions

- **Diagnostics** — read-only / safe probes
- **Actions** — remediations; often `requiresAdmin`; UI confirms before POST

## Profiles (UI depth gating)

LocalOpsConsole can show different modules depending on the active **profile**:
`Helpdesk`, `Desktop Support`, `Systems Administrator`, `Network Administrator`, `Developer`, `Power User`.

This profile affects **what the UI shows** (sidebar module list). It does not remove backend capabilities: admin-only actions still require elevation and server-side `requiresAdmin` checks remain enforced.

## Tiers (capability depth)

Some modules are tagged with a numeric **tier** (1–10). Higher tiers generally mean deeper/engineer-level workflows and more detailed analysis.

## Internet Health

Module **Internet Health** consolidates Network + VPN + connectivity diagnostics into one Networking sidebar entry.

- **Summary** loads in ~2s (gateway, DNS, public HTTPS, loss/latency, overall %).
- **Connectivity tests** run individually (Gateway, DNS, HTTPS, TCP 80/443, etc.).
- **DNS / Hosts / WINS**, **VPN / Proxy**, adapters, Winsock, TCP/IP, routing, cable, Wi‑Fi, events, timeline.
- **Automatic diagnosis** returns likely cause, recommended repairs, and a decision table.
- **Repairs** (admin): Flush DNS, Renew IP, Reset Winsock/TCP, Clear ARP, Restart adapter, Reset proxy, etc.
- **Speed test** is opt-in only (never auto-runs on page load).

Standalone Network and VPN modules remain as APIs but are hidden from the sidebar.

### Faster startup

Telemetry no longer runs a full `Get-PnpDevice` inventory on every refresh. System page soft-polls cached telemetry; use **Refresh Telemetry** for a forced update. **Get Profile Health** no longer recursively sizes profiles (avoids timeouts).

## Profiles (UI depth gating)
Run the diagnostic **`InternetIsSlow`** to generate a consolidated report that (best-effort) checks:

- DNS health
- Default-gateway reachability + packet loss
- Interface MTU (best-effort)
- Adapter link speed (best-effort)
- TCP global settings (`netsh`)
- Firewall profile summary (quick state)

The report output includes: **Diagnosis checks**, **Probable Cause**, and **Recommended Actions**.

## Modules (quick how-tos)

### Graphics

1. `GetAdapters` — GPU name, driver version, driver date, vendor
2. `OpenVendorUpdatePage` — opens NVIDIA / AMD / Intel driver download page in the browser

### Remote

1. `DiscoverComputers` — neighbors from ARP / SMB connections
2. `ListShares` — SMB shares on a target host (pass computer name)
3. `ListOpenFiles` / `ListSessions` — requires admin + rights on the target
4. `GetRemoteRegistry` — read-only remote registry (admin); `EnsureRemoteRegistry` starts Remote Registry service locally if needed

### SyncMe

Install SyncMe from [https://www.syncme.co.za](https://www.syncme.co.za), then set `syncMePath` in `settings.json` to your SyncMe install folder when needed.

1. `GetStatus` — detects install and API reachability
2. `OpenConsole` — opens SyncMe UI
3. `StartBackup` — runs SyncMe backup script
4. `OpenDownloadPage` — opens the SyncMe setup package directly when SyncMe is missing

### Tools

Classic IT readouts: IpConfig, Netstat, RoutePrint, Arp, Nslookup, Whoami, Hostname, SystemInfo, PowerCfg, DismGetHealth, SfcVerifyOnly, ChkdskStatus, GpResult.

- `Nslookup` — enter a Host / IP in the Tools UI (defaults to `www.microsoft.com`)
- `RouteAdd` (admin) — add a temporary route (Destination + Gateway + Mask); check Permanent for `route -p add`

Repair actions (admin, long-running):

- `SfcScanNow` — `sfc /scannow`
- `DismRestoreHealth` — `DISM /Online /Cleanup-Image /RestoreHealth`

Also: `GpUpdate`.

While any tool runs, the output panel shows a spinner so long commands do not look hung.

### System

Live hardware monitor (header strip + System page):

- CPU / RAM with realtime sparklines (2s poll on System page)
- Network IPv4 plus up/down bandwidth Mb/s sparkline
- Disk I/O read/write MB/s sparkline + IOPS (physical disk `_Total`)
- All fixed disks in a one-at-a-time accordion
- GPU name + driver, battery when present, problem PnP count
- Uptime, last boot, pending reboot

Force refresh: `GET /api/v1/telemetry?force=1`.

### Configuration

Documented Windows settings console (not silent tweaks). Each setting card shows current value, recommended, Microsoft default, risk, restart/logoff needs, and registry/provider path — then **Apply recommended** or **Restore default**.

Categories: **Explorer**, **Privacy**, **Windows Update**, **Taskbar**, **Power**, **Security**. Admin-gated settings require elevation. Insider status is read-only.

### Printers

Custom **Printers** view (Phase 1):

1. Select a printer — detail shows driver, port, jobs, default flag.
2. **Spooler** panel — status/start type; admin: Restart, Kill hung process, Set Automatic.
3. **Queue** — Cancel / Pause / Resume jobs; Clear all (admin).
4. **Network test** — Ping/DNS/TCP 9100·515/HTTP for TCP/IP ports (IPv6 best-effort).
5. **Print events** — recent spooler/PrintService errors.
6. Admin: Recreate TCP/IP port, Remove ghost printer (confirm).

### Remote Support (RustDesk)

RustDesk-only remote support module (no AnyDesk/TeamViewer; **passwords never shown**).

1. Status: installed, version, running, service, ID.
2. Copy ID to clipboard.
3. Open / Start / Stop / Restart service (admin where required).
4. Install from `settings.json` → `rustDeskInstallerUrl` (+ optional SHA-256 / silent args).

### VPN & Network (via Internet Health)

Use **Internet Health** under Networking for VPN status/disconnect, hosts file, WINS, Flush DNS, Renew IP, and connectivity tests. Header still shows a **VPN** chip when connected (never credentials).

### Remote (LAN)

Discover computers → **click a PC** → List shares / sessions / open files (bounded timeouts; TCP 445 probe first).

### Windows Update (module)

- `GetPending`
- Admin: `ResetComponents`, `ClearSoftwareDistribution` (destructive — use carefully)

Other modules: Storage, Services, Security, EventLog, Devices, Power, Users, Audio, Startup — use the in-app Diagnostics / Actions lists.

## Updates (self-hosted)

Host on your marketing site:

- `website/uploads/update.json`
- `website/uploads/builds/LocalOpsConsole-x.y.z.zip`

Example manifest:

```json
{
  "name": "LocalOpsConsole",
  "latest": "1.2.0",
  "releasedAt": "2026-08-05T00:00:00Z",
  "notes": "Release notes",
  "minVersion": "1.0.0",
  "builds": [
    {
      "version": "1.2.0",
      "channel": "stable",
      "url": "uploads/builds/LocalOpsConsole-1.2.0.zip",
      "sha256": "…",
      "size": 0
    }
  ]
}
```

In `settings.json`:

```json
"updateUrl": "https://your.site/uploads/update.json",
"syncMePath": "D:\\Projects\\Personal Projects\\SyncMe"
```

App flow: `GET /api/v1/updates/check` → banner if newer → confirm → `POST /api/v1/updates/apply` (download, verify sha256, extract, restart).

Publish: bump `VERSION`, run `.\build.ps1 -PublishWebsite`, deploy `website/` (or `uploads/`).

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Port in use | Change `settings.json` `port` |
| Access Denied on actions | Confirm UAC elevation; relaunch via `start.bat` |
| Tools command not found | Rebuild/restart after ModuleLoader fix (libs must load before actions) |
| SyncMe not found | Set `syncMePath` in `settings.json` |
| Remote open files fails | Need admin + SMB admin rights on target |
| Remote list shares timed out | Verify firewall plus RPC/WMI/SMB access to target, then retry |
| Update check fails | Test `updateUrl` in browser; validate JSON + sha256 |
| Server won't start | Run `api\server.ps1` directly; read `logs\` |
| Unstyled UI | Use the listener URL, not raw file:// |

## Safety

- Binds to `localhost` only
- Admin actions are explicit
- Remote registry is read-only from this console
- No silent auto-update

---

Copyright 2026 Bradford Lotriet
