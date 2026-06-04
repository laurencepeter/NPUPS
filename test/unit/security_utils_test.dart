import 'package:flutter_test/flutter_test.dart';
import 'package:workforce/services/security_utils.dart';

void main() {
  group('SecurityUtils.maskBankAccount', () {
    test('masks all but the last 4 digits', () {
      expect(
        SecurityUtils.maskBankAccount('1102-4587-6321'),
        '****-****-6321',
      );
    });

    test('returns unchanged when 4 chars or fewer', () {
      expect(SecurityUtils.maskBankAccount('6321'), '6321');
      expect(SecurityUtils.maskBankAccount('21'), '21');
    });

    test('preserves non-digit separators in the visible portion', () {
      final result = SecurityUtils.maskBankAccount('1234567890');
      expect(result.endsWith('7890'), isTrue);
    });
  });

  group('SecurityUtils.maskNisNumber', () {
    test('masks all but the last 5 chars', () {
      expect(
        SecurityUtils.maskNisNumber('NIS-2024-00147'),
        'NIS-****-00147',
      );
    });

    test('returns unchanged when 5 chars or fewer', () {
      expect(SecurityUtils.maskNisNumber('00147'), '00147');
    });
  });

  group('SecurityUtils.maskIdNumber', () {
    test('masks all but the last 3 chars', () {
      expect(
        SecurityUtils.maskIdNumber('ID-TT-198803150'),
        'ID-TT-******150',
      );
    });

    test('returns unchanged when 3 chars or fewer', () {
      expect(SecurityUtils.maskIdNumber('150'), '150');
    });
  });

  group('SecurityUtils.sanitizeFileName', () {
    test('replaces path separators with underscores', () {
      expect(SecurityUtils.sanitizeFileName('foo/bar'), 'foo_bar');
      expect(SecurityUtils.sanitizeFileName('foo\\bar'), 'foo_bar');
    });

    test('eliminates parent directory traversal sequences', () {
      final result = SecurityUtils.sanitizeFileName('../../etc/passwd');
      expect(result.contains('..'), isFalse);
      expect(result.contains('/'), isFalse);
    });

    test('removes null bytes', () {
      expect(SecurityUtils.sanitizeFileName('file\x00name'), 'filename');
    });

    test('truncates to 200 characters', () {
      final long = 'a' * 250;
      expect(SecurityUtils.sanitizeFileName(long).length, 200);
    });

    test('falls back to "export" for blank input', () {
      expect(SecurityUtils.sanitizeFileName('   '), 'export');
    });

    test('strips special characters leaving only safe chars', () {
      final result = SecurityUtils.sanitizeFileName('report<2024>.xlsx');
      expect(result.contains('<'), isFalse);
      expect(result.contains('>'), isFalse);
      expect(result.contains('.'), isTrue);
    });
  });

  group('SecurityUtils.isValidEmail', () {
    test('accepts valid email addresses', () {
      expect(SecurityUtils.isValidEmail('admin@workforce.app'), isTrue);
      expect(SecurityUtils.isValidEmail('user.name+tag@example.co.uk'), isTrue);
    });

    test('rejects invalid email addresses', () {
      expect(SecurityUtils.isValidEmail('notanemail'), isFalse);
      expect(SecurityUtils.isValidEmail('@nodomain'), isFalse);
      expect(SecurityUtils.isValidEmail('missing@tld'), isFalse);
      expect(SecurityUtils.isValidEmail(''), isFalse);
    });

    test('trims surrounding whitespace before validating', () {
      expect(SecurityUtils.isValidEmail('  admin@workforce.app  '), isTrue);
    });
  });
}
