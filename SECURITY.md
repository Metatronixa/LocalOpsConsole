# Security Policy

LocalOpsConsole is a **local-only** Windows diagnostic tool. It is free and open source (MIT).

## Supported versions

Security fixes are applied to the latest release on the `main` branch and published as a new SemVer tag when needed.

| Version | Supported |
|---------|-----------|
| 1.2.x   | Yes       |
| < 1.2   | Best effort |

## Threat model (short)

- The API binds to **localhost** by default (`settings.json` → `bindHost`).
- Remediations that change the system are gated by `requiresAdmin` and UAC elevation.
- Do **not** expose the listener to the network. Changing `bindHost` to a non-loopback address is unsupported for multi-user or internet-facing use.
- Update downloads should use HTTPS and SHA-256 verification via `update.json`.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security-sensitive reports.

Email: **bradford.lotriet@gmail.com** (or open a private security advisory on GitHub if available for this repository).

Include:

1. Description of the issue and impact
2. Steps to reproduce
3. Affected version / commit
4. Any suggested fix (optional)

We aim to acknowledge reports within a few business days and to ship a fix or mitigation as soon as practical.

## Safe usage

- Run from a trusted extract path.
- Prefer elevated sessions only when remediations are required; standard users can still run most diagnostics.
- Review `settings.json` before pointing `updateUrl` or installer URLs at third-party hosts.
- Never paste production secrets into issues or commits.
