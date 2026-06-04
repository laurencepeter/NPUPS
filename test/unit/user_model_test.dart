import 'package:flutter_test/flutter_test.dart';
import 'package:workforce/models/user_model.dart';

void main() {
  group('AppUser.initials', () {
    test('returns first-and-last initials for a two-part name', () {
      const user = AppUser(
        id: 'U1',
        email: 'a@b.com',
        fullName: 'Laurence Peter',
        role: UserRole.systemAdmin,
      );
      expect(user.initials, 'LP');
    });

    test('returns first-and-last initials for a three-part name', () {
      const user = AppUser(
        id: 'U2',
        email: 'a@b.com',
        fullName: 'Marcus James Thompson',
        role: UserRole.regionalCoordinator,
      );
      expect(user.initials, 'MT');
    });

    test('returns first two chars uppercased for a single-word name', () {
      const user = AppUser(
        id: 'U3',
        email: 'a@b.com',
        fullName: 'Priya',
        role: UserRole.hr,
      );
      expect(user.initials, 'PR');
    });

    test('result is always uppercase', () {
      const user = AppUser(
        id: 'U4',
        email: 'a@b.com',
        fullName: 'kevin rampersad',
        role: UserRole.worker,
      );
      expect(user.initials, user.initials.toUpperCase());
    });
  });

  group('AppUser defaults', () {
    test('isActive defaults to true', () {
      const user = AppUser(
        id: 'U5',
        email: 'x@y.com',
        fullName: 'Test User',
        role: UserRole.hr,
      );
      expect(user.isActive, isTrue);
    });

    test('corporationId and corporationName default to null', () {
      const user = AppUser(
        id: 'U6',
        email: 'x@y.com',
        fullName: 'No Corp',
        role: UserRole.ps,
      );
      expect(user.corporationId, isNull);
      expect(user.corporationName, isNull);
    });
  });

  group('UserRole display names', () {
    test('each role has a non-empty displayName', () {
      for (final role in UserRole.values) {
        expect(role.displayName.isNotEmpty, isTrue,
            reason: '${role.name} has empty displayName');
      }
    });

    test('each role has a non-empty description', () {
      for (final role in UserRole.values) {
        expect(role.description.isNotEmpty, isTrue,
            reason: '${role.name} has empty description');
      }
    });
  });
}
