# Storage

## Purpose

Volume inventory, SMART health, capacity trends, and temp cleanup.

## Capabilities

inventory · diagnostics · monitoring · remediation · automation · reporting

## Diagnostics

- `GetDisks`, `SmartStatus`
- `CapacityTrend` — snapshot + local JSONL history
- `SmartHistory` — physical disk health history

## Remediation

`ClearTemp` (admin) — conservative temp cleanup.

## Automation

Rules may opt into `disk-cleanup`. Disabled unless enabled in rule JSON.

## Permissions

Cleanup requires elevation. History writes under `data/storage/`.

## Security implications

Cleanup deletes old user temp files only when invoked. History files stay local.

## Expected runtime

Disks/SMART: 2–15s · Trend/History: &lt;3s plus disk I/O

## Typical use cases

- Low disk warnings
- Drive health before hardware RMA
- Capacity trending for workstations
