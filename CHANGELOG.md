# Changelog

## 2.1.5 — 2026-08-05

### Features

- **Computers remote ops**: processes list + end process, printers, console→PC latency (Ping PC), agent internet net smoke (ping + short download), disk IO in heartbeat telemetry (read/write MB/s).
- **Repair commands**: SFC `/scannow`, read-only CHKDSK, schedule CHKDSK `/F` (no auto-reboot) with confirmations.
- **Tailscale**: document using Tailscale IP in `fleetPublicUrl` / `-ServerUrl` with `bindHost: 0.0.0.0`.
- Agent bumped to **2.1.5** (reinstall/update agents for new command types). Longer API timeouts for result posts; command log lines capped.

### Verify

```powershell
.\tools\smoke-bind.ps1
# With server running:
.\tools\smoke-api.ps1
.\tools\smoke-fleet-commands.ps1
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
