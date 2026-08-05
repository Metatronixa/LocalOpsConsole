# Security Baseline

## Purpose

Audit Windows security controls and produce a score, risk rating, compliance summary, and recommendations.

## Capabilities

- diagnostics
- reporting
- inventory (control inventory)

## Diagnostics

| Name | Description |
|------|-------------|
| Audit | Full baseline pass (Defender, Firewall, BitLocker, TPM, Secure Boot, Credential Guard, LSA, UAC, Update, SMBv1, RDP, WinRM, PS logging, Event Log, AV products, Audit Policy) |
| Report | Same data shaped for export/reporting |

## Remediation

None in-module (read-first). Follow recommendations via elevated OS tools or other modules.

## Automation

Not automated by default. Pair findings with Event Intelligence security rules as needed.

## Permissions

Audit runs without requiring admin for many checks; BitLocker/Secure Boot/optional features may return Unknown without elevation.

## Security implications

Read-only registry/WMI/service queries. Does not change system state.

## Expected runtime

Typically 5–30 seconds depending on WMI and optional feature queries.

## Typical use cases

- Hardening review before handing a PC to a user
- MSP intake checklist
- Compare posture after a policy change
