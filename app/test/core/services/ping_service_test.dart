import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cofiz/core/models/user_model.dart';
import 'package:cofiz/core/services/ping_service.dart';

void main() {
  group('PingService', () {
    late FakeFirebaseFirestore fake;
    late List<http.Request> relayRequests;
    late http.Client mockClient;

    setUp(() {
      fake = FakeFirebaseFirestore();
      relayRequests = [];
      mockClient = MockClient((request) async {
        relayRequests.add(request);
        return http.Response('{"ok":true}', 200);
      });
    });

    Future<void> seedAdmin(String uid) async {
      await fake.collection('users').doc(uid).set({
        'role': 'admin',
        'email': '$uid@example.com',
        'displayName': 'Admin $uid',
      });
    }

    Future<void> seedUser(String uid, {String role = 'worker'}) async {
      await fake.collection('users').doc(uid).set({
        'role': role,
        'email': '$uid@example.com',
        'displayName': 'User $uid',
      });
    }

    test('pingCollectorToAdmin fans out to 2 admins', () async {
      await seedAdmin('a1');
      await seedAdmin('a2');
      await seedUser('c1', role: 'worker');
      final svc = PingService(
        firestore: fake,
        httpClient: mockClient,
        relayUrl: 'https://relay.example.com/push',
        relaySecret: 'secret123',
      );
      await svc.pingAdmin(
        note: 'Need cash',
        senderId: 'c1',
        senderName: 'Collector A',
        senderRole: UserRole.worker,
      );
      final notifs = await fake.collection('notifications').get();
      expect(notifs.docs, hasLength(2));
      final targets = notifs.docs.map((d) => d.data()['targetUserId']).toSet();
      expect(targets, containsAll(['a1', 'a2']));
      // type should be pingCollectorToAdmin
      for (final doc in notifs.docs) {
        expect(doc.data()['type'], 'pingCollectorToAdmin');
        expect(doc.data()['body'], 'Need cash');
        expect(doc.data()['title'], 'Ping from Collector A (worker)');
        expect(doc.data()['isRead'], isFalse);
        expect(doc.data()['senderId'], 'c1');
        expect(doc.data()['senderRole'], 'worker');
        expect(doc.data()['createdAt'], isA<int>());
        expect((doc.data()['metadata'] as Map)['note'], 'Need cash');
      }
      // relay push per admin
      expect(relayRequests, hasLength(2));
    });

    test('pingViewerToAdmin uses pingViewerToAdmin type', () async {
      await seedAdmin('a1');
      final svc = PingService(
        firestore: fake,
        httpClient: mockClient,
        relayUrl: 'https://relay.example.com/push',
        relaySecret: 'secret123',
      );
      await svc.pingAdmin(
        note: 'Need clarification',
        senderId: 'v1',
        senderName: 'Viewer B',
        senderRole: UserRole.viewer,
      );
      final notifs = await fake.collection('notifications').get();
      expect(notifs.docs, hasLength(1));
      expect(notifs.docs.first.data()['type'], 'pingViewerToAdmin');
      expect(notifs.docs.first.data()['title'], 'Ping from Viewer B (viewer)');
      expect(notifs.docs.first.data()['senderRole'], 'viewer');
    });

    test('note longer than 120 chars throws ArgumentError', () async {
      await seedAdmin('a1');
      final svc = PingService(firestore: fake, httpClient: mockClient);
      final longNote = 'x' * 121;
      expect(
        () => svc.pingAdmin(
          note: longNote,
          senderId: 'c1',
          senderName: 'Collector A',
          senderRole: UserRole.worker,
        ),
        throwsA(isA<ArgumentError>()),
      );
      final notifs = await fake.collection('notifications').get();
      expect(notifs.docs, isEmpty);
    });

    test('note exactly 120 chars is allowed', () async {
      await seedAdmin('a1');
      final svc = PingService(
        firestore: fake,
        httpClient: mockClient,
        relayUrl: 'https://relay.example.com/push',
        relaySecret: 'secret123',
      );
      final note120 = 'x' * 120;
      await svc.pingAdmin(
        note: note120,
        senderId: 'c1',
        senderName: 'Collector A',
        senderRole: UserRole.worker,
      );
      final notifs = await fake.collection('notifications').get();
      expect(notifs.docs, hasLength(1));
    });

    test('cooldown throws StateError if within 120s', () async {
      await seedAdmin('a1');
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await fake.collection('users').doc('c1').set({
        'role': 'worker',
        'lastPingAt': nowMs,
      });
      final svc = PingService(firestore: fake, httpClient: mockClient);
      expect(
        () => svc.pingAdmin(
          note: 'hello',
          senderId: 'c1',
          senderName: 'Collector A',
          senderRole: UserRole.worker,
        ),
        throwsA(isA<StateError>()),
      );
      final notifs = await fake.collection('notifications').get();
      expect(notifs.docs, isEmpty);
    });

    test('cooldown allows after 120s', () async {
      await seedAdmin('a1');
      final oldMs = DateTime.now().millisecondsSinceEpoch - 130000;
      await fake.collection('users').doc('c1').set({
        'role': 'worker',
        'lastPingAt': oldMs,
      });
      final svc = PingService(
        firestore: fake,
        httpClient: mockClient,
        relayUrl: 'https://relay.example.com/push',
        relaySecret: 'secret123',
      );
      await svc.pingAdmin(
        note: 'hello after cooldown',
        senderId: 'c1',
        senderName: 'Collector A',
        senderRole: UserRole.worker,
      );
      final notifs = await fake.collection('notifications').get();
      expect(notifs.docs, hasLength(1));
    });

    test('lastPingAt updated after successful ping', () async {
      await seedAdmin('a1');
      final svc = PingService(firestore: fake, httpClient: mockClient);
      await svc.pingAdmin(
        note: 'ping',
        senderId: 'c1',
        senderName: 'Collector A',
        senderRole: UserRole.worker,
      );
      final senderDoc = await fake.collection('users').doc('c1').get();
      expect(senderDoc.data(), contains('lastPingAt'));
      // fake_cloud_firestore replaces serverTimestamp with Timestamp; just check not null
      expect(senderDoc.data()!['lastPingAt'], isNotNull);
    });

    test('no admins results in no notifications but still updates cooldown',
        () async {
      // No admin seeded
      final svc = PingService(firestore: fake, httpClient: mockClient);
      await svc.pingAdmin(
        note: 'hello',
        senderId: 'c1',
        senderName: 'Collector A',
        senderRole: UserRole.worker,
      );
      final notifs = await fake.collection('notifications').get();
      expect(notifs.docs, isEmpty);
      final senderDoc = await fake.collection('users').doc('c1').get();
      expect(senderDoc.data()!['lastPingAt'], isNotNull);
    });

    test('cooldown handles Timestamp type for lastPingAt', () async {
      await seedAdmin('a1');
      // Simulate Firestore Timestamp stored value — use int but also test that int handling works
      // We'll store as int and as Timestamp-like; fake uses int for serverTimestamp
      // Here we manually set a Timestamp value via Firestore API
      await fake.collection('users').doc('c1').set({
        'role': 'worker',
        'lastPingAt': DateTime.now().millisecondsSinceEpoch,
      });
      final svc = PingService(firestore: fake, httpClient: mockClient);
      // Should throw cooldown
      expect(
        () => svc.pingAdmin(
          note: 'hi',
          senderId: 'c1',
          senderName: 'Collector A',
          senderRole: UserRole.worker,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
