# Security Policy

LocalOpsConsole is a **local-first** Windows Operations Platform. It is free and open source (MIT).

## Supported versions

Security fixes target the latest release on `main` and ship as a new SemVer tag.

| Version | Supported |
|---------|-----------|
| 2.1.x   | Yes       |
| 2.0.x   | Best effort |
| &lt; 2.0   | Best effort |

## Threat model (short)

- Default API bind is **localhost** (`settings.json` → `bindHost`).
- Remediations that change the system are gated by `requiresAdmin` and UAC elevation.
- Module execution is gated: manifest → SHA-256 integrity → elevation → deps → params → path jail.
- Packaged builds use `integrityMode: enforce`; source defaults to `warn`.
- Automation is **opt-in** per rule (`automation.enabled`).
- Fleet agents use enrollment tokens then HMAC-signed requests; leave `fleetEnrollToken` empty in committed settings.
- Opening the listener beyond localhost (`bindHost: 0.0.0.0`) is for trusted LAN fleet use only — not internet-facing multi-tenant hosting.
- Update downloads should use HTTPS and SHA-256 verification via `update.json`.
- No mandatory product telemetry.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security-sensitive reports.

Email: **bradford.lotriet@gmail.com** (or open a private security advisory on GitHub if available).

Include:

1. Description of the issue and impact  
2. Steps to reproduce  
3. Affected version / commit  
4. Any suggested fix (optional)

We aim to acknowledge reports within a few business days and to ship a fix or mitigation as soon as practical.

## Safe usage

- Run from a trusted extract path.
- Prefer elevated sessions only when remediations are required; standard users can still run most diagnostics.
- Review `settings.json` before pointing `updateUrl`, `fleetPublicUrl`, or installer URLs at third-party hosts.
- Never paste production secrets or live enroll tokens into issues or commits.
- If Event Intelligence shows PowerShell **4104** events for `api\server.ps1`, that is Script Block Logging of the console host itself — not necessarily an attack.
