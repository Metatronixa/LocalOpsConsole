# Security

## Purpose

Firewall profiles and Microsoft Defender status / quick scan.

## Capabilities

diagnostics · monitoring · remediation

## Diagnostics

- `GetFirewall` — profile enablement and default actions
- `GetDefender` — realtime, signatures, scan ages (fast path with service fallback)

## Remediation

- `QuickScan` (admin) — Defender quick scan; can take several minutes

## Automation

None by default. Pair with Event Intelligence security rules.

## Permissions

Quick Scan requires elevation. Most status queries work as standard user.

## Security implications

Read-mostly. Quick Scan invokes Defender scanning.

## Expected runtime

Firewall/Defender status: typically under a few seconds (12s client timeout). Quick Scan: minutes.

## Typical use cases

- Confirm firewall profiles after a VPN change
- Check Defender realtime / signature age
- Kick off a quick scan during a malware ticket
