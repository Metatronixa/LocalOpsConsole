# Event Log

## Purpose

Bounded Critical/Error event summary for System and Application logs.

## Capabilities

diagnostics · monitoring · reporting

## Diagnostics

- `GetLogSummary` — capped sample counts per log (never unbounded Measure-Object)
- `GetRecentErrors` — recent Critical/Error events in a time window (default 48h)

## Remediation

None — use Incidents / Timeline for correlated Event Intelligence, or OS tools for remediation.

## Automation

None in-module. Event Intelligence rules consume event sources continuously.

## Permissions

System/Application usually readable as standard user. Security log often requires elevation (shown as Access denied).

## Security implications

Read-only. Queries are time-bounded and sample-capped to keep the UI responsive.

## Expected runtime

Typically a few seconds; client timeouts around 15s. Avoid requesting huge MaxEvents/Hours values.

## Typical use cases

- Spot-check recent errors before opening Event Viewer
- Confirm whether Application/System are noisy in the last day
- Hand off to Incident Center when Event Intelligence has correlated issues
