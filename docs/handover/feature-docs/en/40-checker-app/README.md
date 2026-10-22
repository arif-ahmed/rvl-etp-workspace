# 40 · Checker App

Features used by gate staff in the Flutter checker app (`rvl-gobcb-checker-app`), TicketChecker Cognito pool.

[Back to contents](../README.md)

## Sign-in and access

- [X-12 Checker login](../60-cross-cutting/X-12-checker-login.md)
- [X-14 Authorization layer 1: pool schemes and policies](../60-cross-cutting/X-14-authz-pool-policies.md)

## Features in this section

| ID | Feature | Purpose |
|---|---|---|
| C-01 | [Assigned event and gate](C-01-assigned-event-gate.md) | Load the event and gate the checker is assigned to. |
| C-02 | [Ticket download for offline checking](C-02-offline-ticket-download.md) | Download the gate's valid tickets into the device database. |
| C-03 | [QR scan validation](C-03-qr-scan-validation.md) | Scan a ticket QR, verify signature, gate and event offline, mark it used. |
| C-04 | [Manual entry](C-04-manual-entry.md) | Admit a ticket by typing its number when the QR cannot be read. |
| C-05 | [Scan sync](C-05-ticket-sync.md) | Upload local scans and receive other devices' scans every 90 seconds. |
| C-06 | [Signature-only ticket validation](C-06-manual-ticket-validation.md) | Check a QR's signature without gate/event rules or recording an entry. |
