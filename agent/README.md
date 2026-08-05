# LocalOps Agent (v2.0.0)

Outbound Windows fleet agent for [LocalOpsConsole](https://github.com/Metatronixa/LocalOpsConsole). The agent initiates all traffic to the console — no inbound listener on managed PCs.

## Requirements

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1+
- Administrator rights for install
- Network reachability to the LocalOpsConsole server URL

## Install

1. Copy the `agent` folder (or extract `LocalOpsAgent-2.0.0.zip`) to the target PC.
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

## Remote agents and bindHost

By default the console binds to `localhost` (this PC only). Agents on other PCs need:

1. **A reachable ServerUrl** — the PC's LAN IP (e.g. `http://192.168.1.10:8787`), not `127.0.0.1` / `localhost`
2. **HttpListener open to the network** — set `bindHost` in `settings.json` to `0.0.0.0` or that LAN IP

Optional: set `fleetPublicUrl` (e.g. `http://192.168.1.10:8787`) to pin the dashboard install one-liner. If unset, Computers uses the detected LAN IPv4 for the suggested `-ServerUrl`.

## Behavior

- Heartbeat every **30 seconds** (CPU, RAM, disk, network, uptime, etc.)
- Poll for commands every **3 seconds**
- HMAC-SHA256 signed requests after enrollment
- Logs: `C:\ProgramData\LocalOpsAgent\logs\agent-YYYY-MM-DD.log`

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
