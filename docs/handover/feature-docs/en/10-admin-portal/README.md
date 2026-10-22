# 10 · Admin Portal

Features started by BCB/BS23 staff in the Angular admin portal (`rvl-gobcb-admin-portal`), Admin Cognito pool.

[Back to contents](../README.md)

## Sign-in and access

- [X-01 Admin login (phone OTP + password)](../60-cross-cutting/X-01-admin-login.md)
- [X-02 Admin forgot password](../60-cross-cutting/X-02-admin-forgot-password.md)
- [X-03 Admin change password and logout](../60-cross-cutting/X-03-admin-change-password-logout.md)
- [X-04 Admin session handling (token attach and refresh)](../60-cross-cutting/X-04-admin-session.md)
- [X-05 Staff account provisioning](../60-cross-cutting/X-05-admin-provisioning.md)
- [X-15 Authorization layers 2–3: staff roles](../60-cross-cutting/X-15-authz-roles.md)
- [X-16 Authorization layer 4: program scope](../60-cross-cutting/X-16-authz-program-scope.md)
- [X-17 Client-side authorization (menus and guards)](../60-cross-cutting/X-17-authz-client-side.md)

## Features in this section

| ID | Feature | Purpose |
|---|---|---|
| A-01 | [Program selection and program-scoped menu](A-01-program-selection.md) | Pick a program (series/tournament); the portal then sends `X-Program-Id` and shows the program menu. |
| A-02 | [Programs](A-02-programs.md) | Create, edit and delete programs (a series or tournament that groups events). |
| A-03 | [Program settings](A-03-program-settings.md) | Per-program commercial rules: payment gateway, purchase limits, VAT/service charge, ticket prefix. |
| A-04 | [Teams](A-04-teams.md) | Maintain the teams that play in a program's events. |
| A-05 | [Venues and stadium layout](A-05-venues.md) | Define a venue: SVG map, gallery → block → level hierarchy, entry gates and mini gates. |
| A-06 | [Program–venue mapping and venue details](A-06-program-venue-mapping.md) | Attach venues to a program and generate/sync the per-program venue details (price, capacity, currency per level). |
| A-07 | [Events (matches)](A-07-events.md) | Create, edit, segment, publish/unpublish, duplicate and enable/disable events. |
| A-08 | [Event settings override](A-08-event-settings.md) | Override program settings for a single event. |
| A-09 | [Event venue details and per-level pricing](A-09-event-level-pricing.md) | View an event's venue tree and change the price of a level. |
| A-10 | [Event capacity adjustment](A-10-capacity-adjustment.md) | Increase or decrease the sellable capacity of a level for an event. |
| A-11 | [Seat reservation (complimentary / partner)](A-11-seat-reservation.md) | Hold seats outside online sale for complimentary or partner use. |
| A-12 | [Reserved ticket generation and distribution](A-12-reserved-tickets.md) | Generate, sign, merge/zip, download and email the tickets of a reservation ("Generate Tickets" menu). |
| A-13 | [Ticket layouts and ticket attributes](A-13-ticket-layouts.md) | Upload and publish the PDF templates used to print tickets, and the attributes printed on them. |
| A-14 | [Ticket-pricing content page](A-14-ticket-pricing-content.md) | Maintain the public ticket-pricing information page. |
| A-15 | [Promo codes](A-15-promo-codes.md) | Create promo codes with value, limits, validity and program/event/gallery assignment. |
| A-16 | [System discounts](A-16-discounts.md) | Automatic discounts (e.g. early bird) applied without a code. |
| A-17 | [Ticket-checker (gate staff) accounts](A-17-ticket-checker-users.md) | Create and manage the TicketChecker-pool accounts used by gate staff. |
| A-18 | [Gate assignment and download control](A-18-gate-assignment.md) | Assign checkers to an event's gates, force-assign/unassign, reset the ticket-download status. |
| A-19 | [Gate (ticket-checker) reports](A-19-gate-reports.md) | Detailed scan report, duplicate-entry and manual-entry reports, export. |
| A-20 | [Raffle draw](A-20-raffle-draw.md) | Record raffle winners from valid ticket numbers of an event. |
| A-21 | [Dashboard](A-21-dashboard.md) | Program dashboard tiles and charts (sales, upcoming events). |
| A-22 | [Booking, sales, revenue and payment-discrepancy reports](A-22-reports.md) | The Reports menu: booking orders, event-wise/summary sales, revenue, payment discrepancy. |
| A-23 | [Reconciliation lookup](A-23-reconciliation.md) | Find an order by order number, transaction id, phone etc. to resolve customer complaints. |
| A-24 | [User issues and support chat (admin side)](A-24-user-issues-admin.md) | List, update and answer customer issues, with real-time chat. |
| A-25 | [Admin users](A-25-admin-users.md) | Create, edit, disable/enable, delete admin accounts with role and programs. |
| A-26 | [Agent (seller) users](A-26-agent-users.md) | Manage the Agent-pool accounts of offline seller agents. |
| A-27 | [Activity log viewer](A-27-activity-log.md) | Browse the audit trail of changes made through the services. |
| A-28 | [Media configuration (banners, gallery, contact, registration)](A-28-media-configuration.md) | Manage the images and blocks shown on the public portal and app. |
| A-29 | [Content editor (T&C, FAQ, privacy, notice)](A-29-content-editor.md) | Edit the static content pages shown to customers. |
| A-30 | [Header/footer and social-media settings](A-30-header-footer-social.md) | Edit the public header/footer and the social-media links. |
| A-31 | [General notices](A-31-general-notices.md) | Publish notices that the public portal shows. |
