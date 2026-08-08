# Threat Operations

Security event stream for LocalOpsConsole (v2.2.0+). Local-first — events stay under `data/threat/` on the console host.

## What it does

- Live stream of security-relevant events (filters by severity, host, keyword)
- ScriptBlock / encoded command inspection with best-effort decode
- Optional fleet agent forwarder → `POST /api/v1/fleet/threat-telemetry` (HMAC)
- Retention via JSONL + meta (not a cloud SIEM)

## Operator path

1. Open **Security → Threat Operations**
2. Use filters / detail pane / script viewer as needed
3. Correlate with Incident Center and Event Timeline when an alert warrants action

## Agent

Agents with SecurityEventForwarder enabled send compact telemetry to the console. Ensure the agent package is published and agents are updated.

## Related

- In-app: Help → User Guide § Threat Operations
- API: `docs/CONTRACT_BASELINE.md` fleet threat-telemetry route
- Storage: `data/threat/events.jsonl`, `data/threat/meta.json`
