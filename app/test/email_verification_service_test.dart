import 'package:cofiz/core/models/user_model.dart';
import 'package:cofiz/core/services/email_verification_service.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser baseUser({bool emailVerified = false}) {
  return AppUser(
    uid: 'u1',
    email: 'a@b.com',
    displayName: 'A',
    role: UserRole.worker,
    workerId: 'w1',
    createdAt: DateTime(2026, 8, 15),
    isActive: true,
    emailVerified: emailVerified,
  );
}

void main() {
  group('AppUser.emailVerified', () {
    test('toFirestore includes emailVerified true', () {
      final u = baseUser(emailVerified: true);
      expect(u.toFirestore()['emailVerified'], true);
    });

    test('toFirestore includes emailVerified false', () {
      final u = baseUser(emailVerified: false);
      expect(u.toFirestore()['emailVerified'], false);
    });

    test('fromFirestore reads emailVerified back', () {
      final doc = baseUser(emailVerified: true).toFirestore();
      final back = AppUser.fromFirestore(doc, 'u1');
      expect(back.emailVerified, true);
    });

    test('fromFirestore defaults emailVerified to false when absent', () {
      final back = AppUser.fromFirestore(
        {'email': 'a@b.com', 'role': 'viewer'},
        'u1',
      );
      expect(back.emailVerified, false);
    });

    test('constructor defaults emailVerified to false', () {
      final u = AppUser(
        uid: 'u1',
        email: 'a@b.com',
        displayName: 'A',
        role: UserRole.worker,
        createdAt: DateTime(2026, 8, 15),
      );
      expect(u.emailVerified, false);
    });

    test('copyWith sets emailVerified', () {
      final u = baseUser().copyWith(emailVerified: true);
      expect(u.emailVerified, true);
    });

    test('toJson and fromJson round-trip emailVerified', () {
      final json = baseUser(emailVerified: true).toJson();
      expect(json['emailVerified'], true);
      final back = AppUser.fromJson(json);
      expect(back.emailVerified, true);
    });
  });

  group('EmailVerificationService', () {
    test('is constructible and exposes the callable API surface', () {
      final service = EmailVerificationService();
      expect(service, isA<EmailVerificationService>());
      final Future<void> Function(String) requestCode = service.requestCode;
      final Future<bool> Function(String) verifyCode = service.verifyCode;
      expect(requestCode, isNotNull);
      expect(verifyCode, isNotNull);
    });
  });
}
