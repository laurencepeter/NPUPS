# NPUPS Platform — User Guide

**National Programme for the Upkeep of Public Spaces**
Ministry of Rural Development & Local Government
Republic of Trinidad and Tobago

---

## Table of Contents

1. [Platform Overview](#1-platform-overview)
2. [Accessing the Platform](#2-accessing-the-platform)
3. [Login Screen](#3-login-screen)
4. [User Roles](#4-user-roles)
5. [Dashboard](#5-dashboard)
6. [Timesheet Approval Pipeline](#6-timesheet-approval-pipeline)
7. [Role-by-Role Guide](#7-role-by-role-guide)
   - [Worker](#71-worker)
   - [Regional Coordinator](#72-regional-coordinator)
   - [HR Department](#73-hr-department)
   - [Accounts (Sub & Main)](#74-accounts-sub--main)
   - [Permanent Secretary (PS)](#75-permanent-secretary-ps)
   - [System Administrator](#76-system-administrator)
8. [Worker Registry](#8-worker-registry)
9. [Excel Export](#9-excel-export)
10. [Network & Security Requirements](#10-network--security-requirements)

---

## 1. Platform Overview

NPUPS is a web-based digital system for managing worker registration, fortnightly timesheet submission, and payroll processing for public space workers under the National Programme for the Upkeep of Public Spaces.

The platform enforces a structured, multi-stage approval workflow ensuring timesheets pass through Worker → Coordinator → HR → Accounts before payment is authorised and exported for payroll processing.

### Key Capabilities

- Fortnightly timesheet submission and digital approval workflow
- Role-based access control with 8 distinct user roles
- Worker profile management with document verification tracking
- Payroll calculation (Wage + COLA + Allowance)
- Excel export matching the official NPUPS timesheet template
- Executive pipeline oversight for the Permanent Secretary

---

## 2. Accessing the Platform

Open any modern web browser and navigate to the platform URL provided by your System Administrator.

**Supported Browsers:** Google Chrome, Mozilla Firefox, Microsoft Edge (latest versions)

**Recommended Resolution:** 1280×720 or higher

You will be presented with the Login Screen upon accessing the URL.

---

## 3. Login Screen

### What You See

The login screen displays:
- The NPUPS logo and Ministry branding at the top
- An **Email Address** field
- A **Password** field with a show/hide toggle
- A **Login** button
- A "View Demo Accounts" option at the bottom (for testing environments only)

### How to Log In

1. Enter your assigned government email address (e.g., `firstname.lastname@npups.gov.tt`)
2. Enter your password
3. Click **Login**

If your credentials are correct, you will be directed to your role-specific Dashboard.

If you receive an error:
- Check that Caps Lock is off
- Verify you are using the correct email format
- Contact your System Administrator if the problem persists

> **Note:** The "Demo Accounts" sheet at the bottom of the login screen is only available in test/staging environments and should not appear in production.

---

## 4. User Roles

Each user is assigned exactly one role. The role determines which screens and actions are available to you.

| Role | Responsibility |
|------|---------------|
| **Worker** | Submit your own fortnightly timesheet |
| **Regional Coordinator** | Enter group timesheets; review and approve worker submissions |
| **HR Department** | Verify employment compliance and leave; approve to Accounts |
| **Sub-Accounts Clerk** | Verify payroll calculations and bank details; approve for payment |
| **Main Accounts Clerk** | Authorise approved payments; manage cheque processing |
| **Permanent Secretary (PS)** | Executive oversight of the full pipeline; bottleneck detection |
| **DMCR** | Worker data compilation and coordination |
| **System Administrator** | Full system access; user management |

Your role is assigned by the System Administrator and cannot be changed by the user.

---

## 5. Dashboard

After logging in, all users land on the **Dashboard** — their personalised overview screen.

### What You See

- **Welcome Card** at the top — displays your name and current date
- **KPI Cards** (6 cards) — key statistics relevant to your role, such as:
  - Number of timesheets pending your action
  - Total workers in your region
  - Payroll totals
  - Stalled/overdue items
- **Quick Actions** — shortcut buttons to the most common tasks for your role
- **Recent Activity** — a log of recent events related to your work
- **Notification Bell** (top right) — future feature; currently a placeholder

The dashboard updates automatically to reflect live pipeline data.

---

## 6. Timesheet Approval Pipeline

Every timesheet in the system moves through the following stages in order:

```
[Worker]          Not Started → Draft → Submitted
                                              ↓
[Regional Coordinator]              Coordinator Review
                                              ↓  (approve)
[HR Department]                       HR Processing
                                              ↓  (approve)
[Accounts]                          Accounts Processing
                                              ↓  (approve)
                                    Approved for Payment
                                              ↓
                                     Exported (.xlsx)
                                              ↓
                                    Cheque / Direct Deposit
```

**Rejection at any stage** sends the timesheet back to the previous stage. The rejecting officer must provide a reason/note. The originating party is notified and must correct and resubmit.

### Stage Colours

| Colour | Meaning |
|--------|---------|
| Grey | Not Started |
| Blue | Draft |
| Orange | Submitted / Under Review |
| Purple | HR Processing |
| Teal | Accounts Processing |
| Green | Approved for Payment |
| Dark Green | Exported |

---

## 7. Role-by-Role Guide

---

### 7.1 Worker

**Navigation Tabs:** Timesheet · Workers

#### My Timesheet

This is your primary screen. It shows your current fortnightly timesheet.

**Read-Only Fields (pre-filled by the system):**
- Full Name, Position, NIS Number, ID Number
- Wage Rate, COLA Rate, Allowance Rate
- Bank Name, Account Number, Branch

**Editable Fields (only when timesheet is in Draft or Not Started stage):**
- **Daily Attendance** — for each of the 14 days in the fortnight:
  - Time In (e.g., 07:00)
  - Time Out (e.g., 15:00)
- **Allowance Days** — number of days allowance applies
- **Remarks** — any notes relevant to the fortnight

**Totals Card** (auto-calculated, read-only):
- Days Worked
- Wage Total
- COLA Total
- Allowance Total
- **Grand Total**

**Pipeline Progress Tracker** — a visual indicator showing which stage your timesheet is currently at and whether it has been approved or rejected at each stage.

**Approval History** — shows who reviewed your timesheet, their decision, and any notes left.

#### Actions

| Button | Effect |
|--------|--------|
| **Save Draft** | Saves your entries without submitting; you can continue editing later |
| **Submit** | Locks your entries and sends the timesheet to your Regional Coordinator for review |

> Once submitted, you **cannot edit** your timesheet unless a Coordinator rejects it back to you.

---

### 7.2 Regional Coordinator

**Navigation Tabs:** Dashboard · Review · Timesheet · Workers

#### Review Tab

This is your primary work screen. It shows all timesheets that have been submitted by workers in your region and are awaiting your review.

**What You See Per Timesheet Card:**
- Worker name and position
- Corporation / Electoral District
- Days worked
- Calculated total amount
- Current stage indicator
- Time the timesheet has been waiting in queue

**Summary Bar (top of screen):**
- Total timesheets in queue
- Total days outstanding
- Combined payroll value

#### Approving Timesheets

- **Single Approve** — tap the green Approve button on an individual card
- **Batch Approve** — use the checkbox to select multiple timesheets, then tap "Approve Selected"
- Approved timesheets advance to **HR Processing**

#### Rejecting a Timesheet

1. Tap **Reject** on the timesheet card
2. A dialog appears — enter a clear rejection reason (e.g., "Incorrect time entries for Day 3 and Day 7")
3. Tap **Confirm Reject**
4. The timesheet is returned to the worker in Draft stage with your note visible

#### Timesheet Entry Tab

Used to digitally enter a **paper timesheet group** on behalf of workers who do not have digital access.

**Header Fields:**
- Corporation
- Electoral District
- Group Number (1–12)
- Fortnight Start Date and End Date

**Worker Rows (up to 12 per group):**
- Worker name (select from registry)
- Daily attendance: Time In / Time Out for each of 14 days
- Allowance days
- Remarks

After entry, tap **Supervisor Confirmation** and then **Submit** to advance the group timesheet into the pipeline.

---

### 7.3 HR Department

**Navigation Tabs:** Dashboard · HR Review · Workers

#### HR Review Tab

Shows all timesheets that have been approved by a Regional Coordinator and are now at the **HR Processing** stage.

**Your Responsibility:**
- Verify the worker is actively employed
- Confirm leave has been correctly recorded
- Check compliance with programme conditions

**Timesheet Card Shows:**
- Worker name, position, corporation
- Wage/COLA/allowance amounts
- Stage history with coordinator's approval note

#### Actions

| Button | Effect |
|--------|--------|
| **Approve** | Advances timesheet to Accounts Processing |
| **Reject** | Returns to Coordinator Review; you must provide a rejection note |

---

### 7.4 Accounts (Sub & Main)

**Navigation Tabs:** Dashboard · Accounts · Export

#### Accounts Tab — Three Sub-Tabs

**1. Pending**

Timesheets at the **Accounts Processing** stage awaiting your verification.

For each timesheet, verify:
- Wage rate, COLA rate, and allowance rate are correct
- Days worked matches attendance records
- Calculated totals are accurate
- Bank name, account number, and branch are correct

| Button | Effect |
|--------|--------|
| **Approve** | Moves timesheet to "Approved for Payment" |
| **Reject** | Returns to HR Processing; rejection note required |
| **Export** | Generates the .xlsx file for this timesheet immediately |

**2. Approved**

Timesheets verified and marked **Approved for Payment**, awaiting batch export or cheque processing.

**3. Exported**

A record of timesheets that have already been exported to .xlsx format for payroll.

#### Export Tab

Used to generate the official NPUPS timesheet Excel file for a corporation group.

**Steps:**

1. Select **Corporation** from the dropdown
2. Select **Group Number** (1–12)
3. Choose the **Fortnight Start Date** (the system automatically snaps to the correct Monday)
4. Review the pre-populated worker list
5. Click **Generate Export**

The system downloads a `.xlsx` file formatted to match the official NPUPS timesheet template, including:
- Title header with group number, corporation, and fortnight dates
- Worker rows with daily Time In/Time Out
- Calculated Wage, COLA, Allowance, and Total columns
- Signature lines for Supervisor, Coordinator, and Corporation

---

### 7.5 Permanent Secretary (PS)

**Navigation Tabs:** Pipeline · Drill Down · Bottlenecks · Workers · Export

The PS dashboard provides **executive-level visibility** across the entire programme.

#### Pipeline Tab

A horizontal visual flow showing all pipeline stages and the number of timesheets currently sitting at each stage. Provides an at-a-glance view of programme throughput.

**Stages displayed (left to right):**
Not Started → Draft → Submitted → Coordinator Review → HR Processing → Accounts Processing → Approved for Payment → Exported → Cheque/Deposit

Each stage shows:
- Count of timesheets currently at that stage
- Stage colour indicator

#### Drill Down Tab

Detailed breakdown with filters:

| Filter | Options |
|--------|---------|
| Corporation | All or specific corporation |
| Stage | Any pipeline stage |
| Date Range | Fortnight period |
| Worker | Search by name or ID |
| Overdue | Show only overdue items |

Use this tab to investigate specific regions or departments and view individual timesheet details.

#### Bottlenecks Tab

Automatically surfaces timesheets that have been **stalled at the same stage for more than 48 hours** (configurable threshold).

Displays:
- Worker name and timesheet details
- Stage where it is stuck
- Duration stalled
- Responsible role/person

Use this to identify where the pipeline is blocked and take corrective action.

---

### 7.6 System Administrator

**Navigation Tabs:** Dashboard · Timesheet · Workers · Export

The System Administrator has **full access** to all functions across all roles and corporations. Use this account for:

- Registering new users and assigning roles
- Managing worker registry (add, edit, deactivate workers)
- Monitoring overall system health
- Performing exports on behalf of any corporation
- Troubleshooting stalled timesheets

---

## 8. Worker Registry

Accessible by all roles via the **Workers** tab.

### Worker List Screen

Displays all registered workers with:
- Profile photo / initials avatar
- Full name and position
- Corporation
- Document verification progress bar and status badge
- Last registered date

**Search:** Type any part of a worker's name, NIS number, or ID number.

**Filters:**
- Document Status: All / Verified / Partial / Missing
- Corporation: All or specific corporation

### Worker Detail Screen

Tap any worker card to open their full profile.

**Sections:**

**Personal Information**
- Full Name, Date of Birth
- NIS Number, National ID Number
- Position, Electoral District

**Bank Information**
- Bank Name, Account Number, Branch

**Document Verification**

Tracks the 5 required compliance documents:

| Document | Statuses |
|----------|---------|
| NIS Registration Card | Missing / Pending / Uploaded |
| Birth Certificate | Missing / Pending / Uploaded |
| Bank Letter | Missing / Pending / Uploaded |
| National ID | Missing / Pending / Uploaded |
| Police Certificate | Missing / Pending / Uploaded |

A progress bar and colour-coded badge show overall verification status:
- **Green (Verified)** — all 5 documents uploaded
- **Orange (Partial)** — some documents uploaded
- **Red (Missing)** — no documents on file

Authorised users can initiate a document upload from this screen.

---

## 9. Excel Export

The exported `.xlsx` file matches the official NPUPS paper timesheet template and is suitable for payroll processing.

**File Contents:**

| Section | Details |
|---------|---------|
| Header | "TIMESHEET" title, Group Number, Corporation, Fortnight dates |
| Column Headers | Date/Position, Mon–Sun (14 days), Days Worked, Wage Rate, COLA Rate, Allowance Rate, Total, Remarks |
| Worker Rows | Name, Position, NIS, ID, Time In/Out per day, allowance days, calculated totals |
| Footer | Supervisor signature line, Coordinator signature line, Corporation signature line |

Cells are formatted with borders, alignment, and government-standard styling.

---

## 10. Network & Security Requirements

### Ports Required on the Server Firewall

| Port | Protocol | Purpose | Required |
|------|----------|---------|---------|
| **443** | HTTPS/TLS | Encrypted web traffic (primary access) | **Yes — mandatory** |
| **80** | HTTP | Should redirect to 443 only | Yes (redirect only) |

> **Port 443 is mandatory.** As this platform is deployed on a government network and handles personal employee data (NIS numbers, national ID, bank account details, payroll information), all traffic **must** be encrypted using TLS 1.2 or higher. HTTP on port 80 should only be used to issue an automatic redirect to HTTPS — it should never serve application content in plaintext.

### Why HTTPS Is Required on a Government Network

- **Legal compliance** — GoRTT and public sector ICT policies require encryption of personally identifiable information (PII) in transit
- **Data protection** — NIS numbers, bank account details, and payroll figures are sensitive financial data
- **Authentication security** — login credentials must not be transmitted in plaintext
- **Browser requirements** — modern browsers flag plain HTTP sites as "Not Secure", which affects usability and trust

### SSL/TLS Certificate

Obtain a certificate from:
- A government-managed Certificate Authority (preferred for .gov.tt domains)
- A trusted public CA (e.g., Let's Encrypt, DigiCert) if approved by your IT department

Configure Nginx to use the certificate in the server block listening on port 443, and add an HTTP-to-HTTPS redirect on port 80.

---

*Document Version: 1.0 — March 2026*
*Prepared for: Ministry of Rural Development & Local Government, Republic of Trinidad and Tobago*
