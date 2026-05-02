// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Provides data masking for sensitive PII (NIS, bank accounts, ID numbers)
// and input sanitization for file names and user inputs.
// ──────────────────────────────────────────────────────────────────────────────

class SecurityUtils {
  SecurityUtils._();

  /// Mask a bank account number, showing only the last 4 characters.
  /// e.g., "1102-4587-6321" -> "****-****-6321"
  static String maskBankAccount(String accountNumber) {
    if (accountNumber.length <= 4) return accountNumber;
    final visible = accountNumber.substring(accountNumber.length - 4);
    final masked = accountNumber.substring(0, accountNumber.length - 4);
    return masked.replaceAll(RegExp(r'[0-9]'), '*') + visible;
  }

  /// Mask a NIS number, showing only the last 5 characters.
  /// e.g., "NIS-2024-00147" -> "NIS-****-*0147"
  static String maskNisNumber(String nisNumber) {
    if (nisNumber.length <= 5) return nisNumber;
    final visible = nisNumber.substring(nisNumber.length - 5);
    final masked = nisNumber.substring(0, nisNumber.length - 5);
    return masked.replaceAll(RegExp(r'[0-9]'), '*') + visible;
  }

  /// Mask an ID number, showing only the last 3 characters.
  /// e.g., "ID-TT-198803150" -> "ID-TT-******150"
  static String maskIdNumber(String idNumber) {
    if (idNumber.length <= 3) return idNumber;
    final visible = idNumber.substring(idNumber.length - 3);
    final masked = idNumber.substring(0, idNumber.length - 3);
    return masked.replaceAll(RegExp(r'[0-9]'), '*') + visible;
  }

  /// Sanitize a file name to prevent path traversal and invalid characters.
  /// Removes directory separators, null bytes, and restricts to safe chars.
  static String sanitizeFileName(String fileName) {
    // Remove null bytes
    var safe = fileName.replaceAll('\x00', '');
    // Remove path separators and parent directory references
    safe = safe.replaceAll(RegExp(r'[/\\]'), '_');
    safe = safe.replaceAll('..', '_');
    // Keep only alphanumeric, hyphens, underscores, dots, and spaces
    safe = safe.replaceAll(RegExp(r'[^a-zA-Z0-9._\- ]'), '_');
    // Limit length
    if (safe.length > 200) safe = safe.substring(0, 200);
    // Ensure it's not empty
    if (safe.trim().isEmpty) safe = 'export';
    return safe;
  }

  /// Validate that a string looks like an email address (basic check).
  static bool isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email.trim());
  }
}
