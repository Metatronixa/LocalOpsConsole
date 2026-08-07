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
- Automation is **opt-in** via the Automation page UI toggles (prefs in `data/automation/`; shipped rules stay disabled by default).
- Fleet agents use enrollment tokens then HMAC-signed requests; leave `fleetEnrollToken` empty in committed settings.
- Opening the listener beyond localhost (`bindHost: 0.0.0.0`) is for trusted LAN fleet use only — not internet-facing multi-tenant hosting.
- Update downloads should use HTTPS and SHA-256 verification via `update.json`.
- No mandatory product telemetry.

## Privacy (POPIA-oriented)

LocalOpsConsole processes IT and operations data (hostnames, telemetry, logs, inventory, fleet command results) **on systems you control**. There is no mandatory telemetry to Bradford Lotriet, opsconsole.co.za, or any vendor cloud.

If you enroll fleet agents, that data stays on **your** console host and agents. You (or your organisation) are the party responsible for deciding what is processed, who may access the console, and how long data is retained under applicable law, including South Africa's Protection of Personal Information Act (POPIA) where it applies.

The marketing site and update feed at [opsconsole.co.za](https://www.opsconsole.co.za/) may use normal web server logs. They do not receive live console or agent telemetry. Full privacy and liability terms: [Legal](https://www.opsconsole.co.za/legal.html).

## Disclaimer and limitation of liability

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT.

IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. THIS INCLUDES, WITHOUT LIMITATION, LOSS OF DATA, BUSINESS INTERRUPTION, FAILED OR PARTIAL REMEDIATIONS, SILENT SOFTWARE INSTALLS, FLEET AGENT ACTIONS, SECURITY BASELINE OR POLICY CHANGES, THIRD-PARTY INSTALLERS, AND ANY CONSEQUENTIAL OR INCIDENTAL DAMAGES.

You accept all risk of use. Review commands before you run them. Prefer elevated sessions only when remediations are required. The MIT [LICENSE](LICENSE) governs distribution and liability.

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
- This product does not embed third-party SCA tools (for example Snyk). Dependency or code scanning, if any, is your optional tooling outside the app.
