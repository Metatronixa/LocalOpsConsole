# Internet Health / Network

## Purpose

Live network health, DNS analytics, connectivity tests, and repair workflows.

## Capabilities

inventory · diagnostics · monitoring · remediation · analytics · reporting

## Diagnostics

Health summary, connectivity, DNS, adapters, Wi‑Fi, routes, VPN health, events, timeline, optional speed test (see `InternetSlow` module). Hidden `network` module provides lower-level DNS/hosts helpers.

## Remediation

DNS set/reset, Winsock/TCP reset, adapter restart, DHCP release, proxy reset (admin where marked).

## Automation

`network-down` ships a **Careful** `network-soft-repair` playbook (DNS flush + DHCP release/renew). Off by default — enable on the **Automation** page. Does not run Winsock/TCP reset.

## Permissions

Many repairs require elevation. Tests are generally standard-user safe.

## Security implications

Winsock/TCP resets require reboot awareness. Changing DNS affects name resolution for all apps.

## Expected runtime

Summary: &lt;5s · Full diagnosis: 15–90s · Speed test: optional and longer

## Typical use cases

- “Internet is slow” tickets
- DNS misconfiguration
- VPN tunnel health checks
