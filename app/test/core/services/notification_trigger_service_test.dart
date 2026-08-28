import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/notification_model.dart';
import 'package:cofiz/core/services/notification_trigger_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  /// Seed a user doc and fire a money-distributed notification at them.
  Future<void> triggerFor(
    String uid, {
    bool? emailVerified,
    bool? emailNotificationsEnabled,
  }) async {
    await firestore.collection('users').doc(uid).set({
      'email': '$uid@example.com',
      if (emailVerified != null) 'emailVerified': emailVerified,
      if (emailNotificationsEnabled != null)
        'emailNotificationsEnabled': emailNotificationsEnabled,
    });
    final svc = NotificationTriggerService(firestore: firestore);
    await svc.notifyMoneyDistributed(
      workerId: 'w1',
      workerUserId: uid,
      workerName: 'Worker',
      amount: 100,
      adminName: 'Admin',
    );
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  test('notification doc is always created (push path unchanged)', () async {
    await triggerFor('u1', emailVerified: false);
    final notifications = await firestore.collection('notifications').get();
    expect(notifications.docs.length, 1);
    expect(notifications.docs.first.data()['type'],
        NotificationType.moneyDistributed.name);
  });

  test('no mail queued when user is not verified', () async {
    await triggerFor('u2',
        emailVerified: false, emailNotificationsEnabled: true);
    final mail = await firestore.collection('mail').get();
    expect(mail.docs, isEmpty);
  });

  test('mail queued when user is verified and opted in', () async {
    await triggerFor('u3',
        emailVerified: true, emailNotificationsEnabled: true);
    final mail = await firestore.collection('mail').get();
    expect(mail.docs.length, 1);
    final data = mail.docs.first.data();
    expect(data['to'], 'u3@example.com');
    expect((data['template'] as Map)['name'], 'notification');
  });

  test('no mail queued when user is verified but opted out', () async {
    await triggerFor('u4',
        emailVerified: true, emailNotificationsEnabled: false);
    final mail = await firestore.collection('mail').get();
    expect(mail.docs, isEmpty);
  });

  test('no mail queued when user has no preference flags yet', () async {
    // Fresh users have neither flag; default must be no email.
    await triggerFor('u5');
    final mail = await firestore.collection('mail').get();
    expect(mail.docs, isEmpty);
  });

  // --- Task 1: ping-only — admin echo removed (RED phase) ---
  test('purchase does not notify admins (ping-only) — low balance', () async {
    // Seed an admin so _notifyAllAdmins would have had a target before the fix.
    await firestore.collection('users').doc('admin1').set({
      'role': 'admin',
      'email': 'admin1@example.com',
    });
    final svc = NotificationTriggerService(firestore: firestore);
    await svc.checkLowBalance(
      workerId: 'w1',
      workerUserId: 'u1',
      workerName: 'A',
      newBalance: 100,
    );
    final notifications = await firestore.collection('notifications').get();
    expect(notifications.docs, isEmpty,
        reason: 'admin echo removed: lowBalance must not create notifications');
    final mail = await firestore.collection('mail').get();
    expect(mail.docs, isEmpty);
  });

  test('large purchase does not notify admins (ping-only)', () async {
    await firestore.collection('users').doc('admin1').set({
      'role': 'admin',
      'email': 'admin1@example.com',
    });
    await firestore.collection('users').doc('admin2').set({
      'role': 'admin',
      'email': 'admin2@example.com',
    });
    final svc = NotificationTriggerService(firestore: firestore);
    await svc.checkLargePurchase(
      workerId: 'w1',
      workerName: 'A',
      amount: 15000,
      coffeeType: 'Yirgacheffe',
      weight: 10,
    );
    final notifications = await firestore.collection('notifications').get();
    expect(notifications.docs, isEmpty,
        reason: 'admin echo removed: largePurchase must not create notifications');
    final mail = await firestore.collection('mail').get();
    expect(mail.docs, isEmpty);
  });
}
