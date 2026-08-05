# Services

## Purpose

Inventory and control Windows services with dependency maps, failure history, and critical profile monitoring.

## Capabilities

inventory · diagnostics · monitoring · remediation · automation

## Diagnostics

- `GetServices` — list services
- `DependencyMap` — depends-on / dependents for profile or named service
- `FailureHistory` — SCM-related System log events
- `CriticalMonitor` — compare against `config/services/*.json`

## Remediation

`StartService`, `StopService`, `RestartService` (admin).

## Automation

Event rules may opt into `restart-service` (see Spooler crash rule). Disabled by default.

## Permissions

Control actions require elevation (`requiresAdmin`).

## Security implications

Stopping critical services can degrade the host. Prefer CriticalMonitor before bulk changes.

## Expected runtime

List: &lt;2s · FailureHistory: 2–10s · DependencyMap: 1–5s

## Typical use cases

- Spooler / Defender / Update service recovery
- Dependency investigation before reboot
- Continuous critical service checks via Event Intelligence profiles
