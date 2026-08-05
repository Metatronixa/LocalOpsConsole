# Printers

## Purpose

Printer inventory, queue analytics, driver validation, port diagnostics, and spooler recovery.

## Capabilities

inventory · diagnostics · monitoring · remediation · automation · reporting

## Diagnostics

Includes `GetPrinters`, queue/port/network tests, `QueueAnalytics`, `DriverValidation`, print events.

## Remediation

Spooler restart/kill, clear queue, job control, TCP/IP port recreate, ghost printer removal (admin).

## Automation

`rules/printers/spooler-crash.json` defines opt-in restart → verify → close.

## Permissions

Most remediations require elevation.

## Security implications

Spooler restarts interrupt printing briefly. Port recreation can disrupt networked printers if misconfigured.

## Expected runtime

Inventory: 1–5s · Network tests: variable · Analytics: 1–3s

## Typical use cases

- Helpdesk printer offline tickets
- Spooler crash loops
- Driver/port mismatch after Windows upgrades
