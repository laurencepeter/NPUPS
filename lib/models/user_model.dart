// ──────────────────────────────────────────────────────────────────────────────
// NPUPS User Model
// Roles aligned with the timesheet approval pipeline:
//   Worker, Regional Coordinator, HR, Sub-Accounts, Main Accounts, PS, Admin
// ──────────────────────────────────────────────────────────────────────────────

enum UserRole {
  systemAdmin('System Admin', 'Full system access and user management'),
  ps('Permanent Secretary', 'Programme approval and oversight'),
  dmcr('DMCR', 'Worker data compilation and coordination'),
  regionalCoordinator('Regional Coordinator', 'Field operations and timesheet review'),
  hr('HR Department', 'Employment processing, compliance, and leave verification'),
  subAccounts('Sub-Accounts Clerk', 'Payroll processing, pay verification, and export'),
  mainAccounts('Main Accounts Clerk', 'Payment authorisation and cheque management'),
  worker('Worker', 'Timesheet entry and submission');

  const UserRole(this.displayName, this.description);
  final String displayName;
  final String description;
}

class NpupsUser {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String? corporationId;
  final String? corporationName;
  final bool isActive;

  const NpupsUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.corporationId,
    this.corporationName,
    this.isActive = true,
  });

  String get initials {
    final parts = fullName.split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.substring(0, 2).toUpperCase();
  }
}
