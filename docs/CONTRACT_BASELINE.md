# API Contract Baseline

Captured for expansion Phase 1. Envelope for all JSON responses:

```json
{ "Success": true, "Message": "", "Timestamp": "yyyy-MM-dd HH:mm:ss", "Data": {} }
```

Prefix: `/api/v1`. Oversized source inventory (lines) at capture time: `core/Fleet.ps1` 2153, `agent/LocalOpsAgent.ps1` 1363, `api/router.ps1` 990, `core/AutomationEngine.ps1` 718, `core/TaskRunner.ps1` 450, `core/NotificationManager.ps1` 404, `core/HealthMonitor.ps1` 329, `core/ModuleLoader.ps1` 294, `core/FleetStore.ps1` 275, `core/Updater.ps1` 269, `core/EventStore.ps1` 263.

## Built-in routes

| Method | Path | Notes |
|--------|------|--------|
| GET | `/health` | Version, admin, module count/errors, PS/Windows, Status, Edition, ProductMode, Sku |
| GET | `/license` | Safe license summary (Valid, Edition, Sku, ProductMode, …) — never raw key |
| GET | `/modules` | Module descriptors (id, diagnostics, actions, profiles, capabilities, requiredEdition, …) |
| GET | `/logs?lines=` | Console feed tail |
| GET | `/telemetry?force=` | Telemetry snapshot |
| POST | `/shutdown` | Stop listener |
| POST | `/restart` | Schedule hidden-window relaunch (`api/server.ps1`), then stop listener |
| GET | `/updates/check` | Update check |
| POST | `/updates/apply` | Body `{ Force? }` — else fall through to Updates module |
| GET | `/integrity/status` | Integrity status |
| GET | `/automation/status` | Automation status |
| POST | `/automation/playbooks/{ruleId}` | Body `{ enabled, scope?, agentIds? }` |
| POST | `/automation/playbooks/{ruleId}/run` | Body `{ agentIds? }` |
| GET | `/settings` | Safe settings (no secrets); includes productMode + license summary |
| POST | `/settings` | Event Intel prefs |
| POST | `/settings/test-channel` | Body `{ channel }` |
| POST | `/syncme/register` | Loopback only |
| POST | `/syncme/heartbeat` | Loopback only |

## Event Intelligence

| Method | Path | Notes |
|--------|------|--------|
| GET | `/events?max=` | Event ring / stored |
| GET | `/alerts?unread=` | Items + Unread |
| POST | `/alerts/{id}/ack` | Acknowledge alert |
| GET | `/incidents?status=&severity=` | Summary + Items |
| GET | `/incidents/{id}` | Incident detail |
| POST | `/incidents/{id}/resolve` | Body `{ Note? }` |
| POST | `/incidents/{id}/ack` | Acknowledge incident |
| GET | `/timeline?max=&hours=` | Global timeline |
| GET | `/rules` | Rule summaries |
| GET/PUT/POST | `/notifications/prefs` | Notification prefs |
| GET | `/security-score` | Security score payload |
| GET | `/health-score` | Health score payload |
| GET | `/heatmap` | Alert heatmap |
| GET | `/event-intel` or `/event-intel/status` | EI status |

## Fleet

HMAC (agent): `POST enroll` (token), `POST heartbeat`, `GET poll`, `POST results`, `POST events`; `GET scripts/{id}/content`; `GET agent-package/manifest|content`; `GET packages/{id}/content`.

Ops:

| Method | Path | Notes |
|--------|------|--------|
| GET | `/fleet/topology` | Topology graph |
| POST | `/fleet/topology/device-type` | Body NodeId + DeviceType (+ MAC/IPv4) |
| GET | `/fleet/agents` | Agent list |
| GET | `/fleet/agents/{id}` | Agent detail |
| POST | `/fleet/agents/{id}/revoke` | Revoke |
| GET | `/fleet/agents/{id}/latency?host=` | Latency probe |
| GET | `/fleet/commands?agentId=` | Command history |
| POST | `/fleet/commands` | Body `{ AgentId, Type, Payload? }` — Type allow-list |
| POST | `/fleet/commands/{id}/cancel` | Body `{ AgentId, Reason? }` |
| POST | `/fleet/commands/clear-stuck` | Body `{ AgentId, Reason? }` |
| GET | `/fleet/alerts` | Fleet alerts |
| GET | `/fleet/scripts` | Script library metadata |
| GET | `/fleet/enroll-token` | Token (ops) |
| POST | `/fleet/enroll-token/rotate` | Rotate |
| GET | `/fleet/policy-packs` | Policy packs |
| GET/POST | `/fleet/packages` | List / register package |
| DELETE | `/fleet/packages/{id}?deleteFiles=` | Remove package |
| GET | `/fleet/agent-package` | Manifest (auto-publish) |
| POST | `/fleet/agent-package/publish` | Publish agent package |
| POST | `/fleet/threat-telemetry` | HMAC agent security telemetry ingest |

### Fleet command Types (allow-list)

`RestartSpooler`, `FlushDns`, `RestartService`, `RunScript`, `Message`, `CollectInventory`, `RestartComputer`, `GetServices`, `GetProcesses`, `EndProcess`, `GetPrinters`, `GetStartupApps`, `GetScheduledTasks`, `NetHealthSmoke`, `DiskCleanup`, `ClearPrintQueue`, `NetworkSoftRepair`, `RestartUpdateStack`, `CaptureProcessSnapshot`, `SfcScannow`, `ChkdskScan`, `ChkdskScheduleFix`, `GetWindowsUpdateStatus`, `InstallWindowsUpdates`, `GetRustDeskStatus`, `InstallRustDesk`, `InstallPackage`, `GetEventLogTail`, `GetResourceOffenders`, `SelfUpdate`, `AuditSecurityBaseline`, `ApplySecurityPolicy`.

`RunScript` uses library `ScriptId` only (not free-form remote script text). New structured type: **`ModuleAction`** with AgentExecutionPayload (`transactionId`, `targetAgentId`, `module`, `action`, `riskLevel`, optional `parameters` / `requiresApproval`). Free-form script fields are rejected.

## Dynamic modules

`GET|POST /api/v1/{module}/{diagnostics|actions}/{name}`

### Infrastructure domain modules (Phase 5)

| Module id | Capabilities | Diagnostics (min) | Actions (min) |
|-----------|--------------|-------------------|---------------|
| activedirectory | AD_DS | DomainHealth, UserStatus, LockoutSource, ReplicationStatus, FSMOStatus | Unlock-ADUser, Reset-ADUserPassword, Set-ADGroupMember |
| dns | DNS | DnsServerHealth, DnsZones, Query-DnsRecord | Clear-DnsServerCache |
| dhcp | DHCP | DhcpServerHealth, DhcpScopes | |
| grouppolicy | GPO | GpoHealth, GpResultSummary | Invoke-GPUpdate |
| hyperv | Hyper-V | HyperVHostHealth, HyperVVmList | Restart-HyperVVm |
| certificates | Certificates | CertificateStoreHealth, ExpiringCertificates | |
| serveroperations | ServerOperations | FileShareHealth, ServerServiceHealth, LocalDiskHealth | Restart-NamedService |

Non-domain / missing role hosts return `Available=false` payloads without crashing.

## Config & intelligence

- `config/risk-matrix.json`, `config/capabilities.json`
- `core/RiskEngine.ps1`, `core/KnowledgeService.ps1`, `core/PlaybookService.ps1`
- `data/knowledge/ad-lockout.json`, `data/playbooks/account-lockout.json`

Re-verify live shapes with `tests/regression/` after each expansion phase.
