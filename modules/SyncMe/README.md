# SyncMe — status, open console, start backup

Integrates the sibling **SyncMe** backup product with LocalOpsConsole when both run on the same PC.

## Self-registration

SyncMe can POST status to LocalOps:

- `POST /api/v1/syncme/register` (alias: `POST /api/v1/syncme/heartbeat`)
- **Loopback-only** in this release (no Bearer token yet)
- Body may include: `installPath`, `version`, `hostname`, `siteId`, `consoleUrl`, `listening`, `success`, `summary`, `setId`, `setName`, `endedUtc`
- Writes `data/syncme/registration.json` (with `receivedUtc`)
- When `installPath` is valid (folder exists and contains `SyncMe-Host.ps1` or `SyncMe.bat`), also sets `settings.syncMePath`

## Path resolution (`Get-SyncMePath`)

1. `settings.syncMePath` if the path exists (manual override)
2. `data/syncme/registration.json` → `installPath` if it exists
3. Sibling folder `..\SyncMe` if it exists

## Diagnostics / actions

| Name | Kind | Purpose |
|------|------|---------|
| GetStatus | diagnostic | Path, console listening, registration / last run |
| OpenConsole | action | Launch SyncMe UI at `http://127.0.0.1:17845/` |
| StartBackup | action | Run `SyncMe-Backup.ps1` |
| OpenDownloadPage | action | Open [syncme.co.za](https://www.syncme.co.za) |

Do not change SyncMe Monitor — that is a separate product.
