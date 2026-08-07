# Changelog

## 2.1.8 — 2026-08-07

### Features

- **Local software catalog**: drop installers under `data/fleet/software/{id}/`, register from Computers → Manage software catalog (winget / local / HTTPS). Agents download local packages over HMAC (LAN `http://` works). Seed includes WinRAR and WinDirStat.
- **Security Baseline fleet target**: same This PC / agent picker as Startup. Run Audit on an enrolled PC via `AuditSecurityBaseline`; sticky status on the page. Open Security Baseline from the Computers drawer. Apply hardening stays on the drawer.
- **Agent baseline audit**: BitLocker, TPM, and Secure Boot checks added alongside Defender and Firewall.
- **Automation Hub playbooks**, Network Map gateway clusters, Startup fleet target, and related polish from the 2.1.8 wave.

### Docs / legal

- User guide and roadmap updated for catalog + Security Baseline fleet.
- Website legal page (POPIA-oriented privacy + limitation of liability); marketing meta tags; version bump.

### Verify

```powershell
.\tools\smoke-bind.ps1
.\tools\smoke-api.ps1
.\tools\smoke-fleet-commands.ps1 -Live
```

**Ops:** Publish agent package, then Update agent on PCs that need local software installs or richer baseline checks.

## 2.1.7 — 2026-08-07

### Bugs fixed

- **Fleet Pending forever**: agent GET poll no longer sends `Content-Type` (PS 5.1 could break `/fleet/poll` while heartbeat still worked).
- **Never-claimed Pending TTL**: Pending with no `ClaimedAt` fails after 10 minutes with a clear message.
- **Short Running timeout**: FlushDns / EventLog / Processes etc. abandon after **5m** (SFC/WU/CHKDSK/policy stay 45m).
- **Agent remove** clears that PC’s Pending/Running commands.
- **UI**: Event Log / WU / Policy / Offenders gated by agent min version; clearer outdated-agent guidance.
- **WU search** on agent soft-timeouts after 90s so the poll loop cannot hang.
- **Smoke** completes in-process claims so live agents are not left blocked.

### Verify

```powershell
.\tools\smoke-bind.ps1
.\tools\smoke-api.ps1
.\tools\smoke-fleet-commands.ps1 -Live
```

**Ops:** on stuck PCs still on agent 2.1.5 — Clear stuck, then **manual reinstall** of LocalOpsAgent 2.3.0 (no SelfUpdate on 2.1.5).

## 2.1.6 — 2026-08-07

### Features

- **Complete HTML User Guide** — full operator walkthrough (install, UI, modules, fleet, SyncMe, settings, troubleshooting) at in-app `/user-guide.html` (Help) and local marketing docs.
- **NetworkMap, SyncMe register, fleet remote-ops polish**.

### Package repair (same 2.1.6)

- **Sanitize release `settings.json`**: never ship developer LAN IPs / enroll tokens / SyncMe paths (`bindHost` forced to `localhost`).
- **Updater timeouts**: remote update check no longer blocks the single-threaded API indefinitely.
- **Fleet stale Running**: fix `[datetime]::TryParse` under PowerShell 5.1 (was throwing during claim).
- Marketing `website/` stays local-only (not on GitHub); bootstrap installer at `scripts/Install-LocalOpsConsole.ps1`.

### Verify

```powershell
.\tools\smoke-bind.ps1
# With server running:
.\tools\smoke-api.ps1
.\tools\smoke-fleet-commands.ps1
.\tools\smoke-fleet-commands.ps1 -Live
```

## 2.1.5 — 2026-08-05

### Features

- **Computers remote ops**: processes list + end process, printers, console→PC latency (Ping PC), agent internet net smoke (ping + short download), disk IO in heartbeat telemetry (read/write MB/s).
- **Repair commands**: SFC `/scannow`, read-only CHKDSK, schedule CHKDSK `/F` (no auto-reboot) with confirmations.
- **Tailscale**: document using Tailscale IP in `fleetPublicUrl` / `-ServerUrl` with `bindHost: 0.0.0.0`.
- Agent bumped to **2.1.5** (reinstall/update agents for new command types). Longer API timeouts for result posts; command log lines capped.

### Package refresh (same 2.1.5)

- Claim **one** command per poll; do not claim while another is Running (fixes piles of Pending/Running during SFC).
- Computers warns when Online but commands Pending &gt;60s, and when agent version is outdated.
- Latency endpoint always returns Success when the probe runs; ICMP result is `ProbeOk` (no false API WARN spam).
- Agent disk IO uses CIM counters (avoids Get-Counter stalling the poll loop).

### Verify

```powershell
.\tools\smoke-bind.ps1
# With server running:
.\tools\smoke-api.ps1
.\tools\smoke-fleet-commands.ps1
.\tools\smoke-fleet-commands.ps1 -Live
```

## 2.1.4 — 2026-08-05

### Bugs fixed

1. **HttpListener failed when `bindHost` was a LAN IP or `0.0.0.0`**  
   Binding a concrete IP (e.g. `172.x.x.x`) often hit “conflicts with an existing registration”. `0.0.0.0` was passed through literally and is not a valid HttpListener wildcard. The server now maps `0.0.0.0` / `*` / `+` to `http://+:port/` and prints clearer conflict hints (port holders, `netsh http show urlacl`, prefer `fleetPublicUrl` for the agent URL).

2. **LAN-only bind broke the local UI (`Failed to fetch`)**  
   The launcher always opens `http://localhost:8787`. Binding only a LAN IP left localhost unreachable. Concrete IP binds now also listen on localhost. Elevated `start.ps1` registers the HTTP.sys URL ACL for non-loopback prefixes.

3. **`fleetPublicUrl` + `bindHost=localhost` silently misled enroll**  
   Computers now surfaces a BindMismatch warning when the suggested agent URL is remote but the console is localhost-only.

### Notes

- For remote agents: set `bindHost` to `0.0.0.0` and put the reachable LAN URL in `fleetPublicUrl` / `-ServerUrl`. Accept UAC on `start.bat`.
- Verify with `.\tools\smoke-bind.ps1` and `.\tools\smoke-api.ps1` (server running).

## 2.1.3 — 2026-08-05

### Changes
- **Computers → Remove** now deletes the agent from the fleet store (PC disappears from the list). Previously revoke only flagged the record.

## 2.1.2 — 2026-08-05

### Changes
- Default update feed is now **`https://www.opsconsole.co.za/uploads/update.json`** (in-app check, bootstrap installers, docs).
- Release ZIPs remain on GitHub Releases; deploy `update.json` to opsconsole.co.za/uploads after each release.

## 2.1.1 — 2026-08-05

### Bugs fixed

1. **Settings API always returned HTTP 405**  
   `GET`/`POST /api/v1/settings` failed because `$method` was never set in `Invoke-LocRouter`. Opening Settings flooded the live console with `Use GET or POST /api/v1/settings`.

2. **Generic module pages blank / "links don't work"**  
   Graphics, SyncMe, Startup, Devices, Power, Users (and similar modules) use `ModuleView`. PowerShell `ConvertTo-Json` can collapse single-item arrays; the UI called `.map()` on a scalar and threw. Fixed with `API.asArray` normalization (client + modules list).

3. **Fleet install URL used localhost for remote PCs**  
   Computers enroll one-liner suggested `http://localhost:8787` when `bindHost` was localhost. Remote agents cannot reach that. Suggested URL now prefers `fleetPublicUrl`, else detected LAN IPv4.

4. **SyncMe "Open download" pointed at a zip URL**  
   Now opens the SyncMe website; zip URL kept as metadata.

5. **Inventory section collapsed by default**  
   Startup/Devices/Graphics/etc. were easy to miss; Inventory opens by default.

### Notes

- Widespread `Failed to fetch` in the UI means the **API process is not running** (nothing on port 8787), not that every module route is broken. Restart with `start.bat`.
- PowerShell Script Block Logging (**Event ID 4104**) for `api\server.ps1` can appear in Timeline/Event Intel when the console starts itself — that is Windows logging the host process, not a crash.

### Verify

```powershell
# With the server running:
.\tools\smoke-api.ps1
```
