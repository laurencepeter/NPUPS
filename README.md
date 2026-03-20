# National Programme for the Upkeep of Public Spaces (NPUPS) 


Worker Registration and Payroll process. The system will serve all 14 Municipal Corporations across Trinidad and Tobago, replacing the current paper-based workflow with an end-to-end digital platform built on Flutter and self-hosted Supabase.
The project covers the complete 6-phase lifecycle as defined in the NPUPS Process Map (ISO 5807 Swimlane Flowchart, Draft 1.0): Programme Initiation, Worker Data Compilation, Employment Processing, Payroll Processing, Payment Authorisation & Disbursement, and Fortnightly Recurring Cycle.
Primary Objectives:
•	Eliminate paper forms from worker registration through payment
•	Provide real-time visibility into worker file status across all 6 departments
•	Automate timesheet collection, Return of Personnel generation, and payroll package assembly
•	Enforce role-based access control (RBAC) with full audit trail
•	Reduce worker time-to-first-payment from weeks to days
•	Deploy to a self-hosted, dockerized environment compliant with government security standards


# Animations & UX
Staggered entrance: Logo → Title → Card → Button fade+slide in sequence (1.4s total)
Floating particles: 20 softly animated dots on the gradient background
Shake on error: Card shakes with elastic curve on invalid login
Pulse glow: Sign-in button has a breathing shadow effect
Page transitions: AnimatedSwitcher with slide+fade between login and authenticated shell
Dashboard cards: Staggered slide-up entrance per card
Process Map Verification
The implementation covers the 6 phases from the ISO 5807 swimlane flowchart:

# Programme Initiation — PS dashboard with approval counts
Worker Data Compilation — DMCR/Coordinator views, document upload placeholder
Employment Processing — HR dashboard with payroll queue and employment notes
Payroll Processing — Sub-Accounts KPIs (pay sheets, vouchers)
Payment & Disbursement — Main Accounts cheque tracking
Fortnightly Cycle — Full timesheet entry screen with 14-day attendance grid, auto-calculations, and sign-off workflow
The background explorer confirmed the repo was empty before my changes — everything is now in place. The commit has been pushed to claude/create-npups-login-template-sWcJb.


# Demo Accounts
Email, Password &	Role

admin@npups.gov.tt	admin123	System Admin — views all data

coordinator@npups.gov.tt	test123	Regional Coordinator — Port of Spain

hr@npups.gov.tt	test123	HR Department — Chaguanas
