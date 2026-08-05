# Changelog

## 2.1.1 — 2026-08-05

### Bugs fixed

1. **Settings API always returned HTTP 405**  
   `GET`/`POST /api/v1/settings` failed because `$method` was never set in `Invoke-LocRouter`. Opening Settings flooded the live console with `Use GET or POST /api/v1/settings`.

2. **Generic module pages blank / “links don’t work”**  
   Graphics, SyncMe, Startup, Devices, Power, Users (and similar modules) use `ModuleView`. PowerShell `ConvertTo-Json` can collapse single-item arrays; the UI called `.map()` on a scalar and threw. Fixed with `API.asArray` normalization (client + modules list).

3. **Fleet install URL used localhost for remote PCs**  
   Computers enroll one-liner suggested `http://localhost:8787` when `bindHost` was localhost. Remote agents cannot reach that. Suggested URL now prefers `fleetPublicUrl`, else detected LAN IPv4.

4. **SyncMe “Open download” pointed at a zip URL**  
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
