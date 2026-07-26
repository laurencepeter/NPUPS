# Platform Walkthrough — Interactive Presentation

`platform-walkthrough.html` is a self-contained, interactive deck that walks
through the WorkForce (NPUPS) platform **from the bottom up** — from the single
timesheet a worker enters, up through every approval stage, to the exact
payment at the top.

## Open it

Double-click `platform-walkthrough.html`, or open it in any modern browser.
It is a single file with no dependencies, network calls, or build step —
suitable for presenting fullscreen or emailing as an attachment.

## Navigate

| Action | Control |
|--------|---------|
| Next / previous slide | `→` / `←` (or `Space`, `PageUp`/`PageDown`), on-screen arrows, or swipe |
| Jump to a slide | Dots on the right edge |
| First / last slide | `Home` / `End` |
| Light / dark theme | ◑ toggle, top-right |

## What's interactive

- **The Ascent** — click any of the nine pipeline stages to see its owner,
  the 48-hour stall watchdog, and what happens on rejection.
- **The automation engine** — drag the sliders (days worked, wage, COLA,
  allowance) and watch the fortnight pay statement recompute to the cent,
  using the app's real formulas (`Timesheet` + `DeductionBreakdown`):
  wage/COLA/allowance totals, gross, NIS at 3.4%, health surcharge, and net.
- **Bottlenecks** — click a risk card to flip it and reveal the mitigation.

## Accuracy

Content is derived from the codebase, not invented:

- Pipeline stages, owners and colours — `lib/models/timesheet_model.dart`
- Deduction rates (NIS 3.4% / 6.5%, health surcharge $8.25/$4.80, threshold
  $469.99) — `lib/models/payroll_deductions_model.dart`
- Backpay delta `(new − old) × days` — `lib/models/backpay_model.dart`
- Tamper-evident audit chain — `lib/models/audit_model.dart`
- Roster defaults and 10-day cap — `lib/models/roster_model.dart`
- Roles, stages and bottleneck detection — `NPUPS_User_Guide.md`

Allowance rate ($25/day) in the calculator is illustrative; all other figures
follow the platform's own logic.
