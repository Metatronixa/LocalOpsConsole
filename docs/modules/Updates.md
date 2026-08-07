# Updates

## Purpose

Windows Update health, pending updates, reboot detection, and component reset.

## Capabilities

diagnostics · monitoring · remediation · reporting

## Diagnostics

- `GetPending` — pending updates + reboot flags
- `UpdateHealth` — score, failure history, servicing events
- `PendingReboot` — reboot reason inventory

## Remediation

`ResetComponents`, `ClearSoftwareDistribution` (admin) — disruptive; confirm first.

## Automation

`update-failed` ships a **Careful** `restart-update-stack` playbook (restart `wuauserv` + BITS only). Off by default — enable on the **Automation** page. Does not clear SoftwareDistribution or install updates.

## Permissions

Reset actions require elevation and can interrupt updates in progress.

## Security implications

Clearing SoftwareDistribution forces re-download. Use when update stack is corrupt.

## Expected runtime

COM search: 5–60s · Health: 5–30s · PendingReboot: &lt;1s

## Typical use cases

- Stuck updates
- Pending reboot before maintenance window
- Failure history for ticket evidence
