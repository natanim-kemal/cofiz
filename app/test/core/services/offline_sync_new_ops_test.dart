import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/services/offline_sync_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';

void main() {
  late Directory dir;
  late FakeFirebaseFirestore fake;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sync_new');
    await OfflineCacheService().initialize(path: dir.path);
    fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    // seed worker
    await fake
        .collection('workers')
        .doc('w1')
        .set({'currentBalance': 1000, 'totalDistributed': 0});
  });
  tearDown(() async => await OfflineCacheService().clearAllCache());
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('queued deleteIncome syncs via transaction', () async {
    await fake.collection('income_records').doc('inc1').set(
        {'amount': 100, 'createdAt': DateTime.now().millisecondsSinceEpoch});
    await OfflineCacheService().queueOperation({
      'opId': 'inc1',
      'type': 'deleteIncome',
      'docId': 'inc1',
      'attempts': 0
    });
    await OfflineSyncService().syncPendingOperations();
    expect((await fake.collection('income_records').doc('inc1').get()).exists,
        isFalse);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });
  test('attempts cap moves to failed box', () async {
    await OfflineCacheService().queueOperation({
      'opId': 'bad',
      'type': 'deleteIncome',
      'docId': 'nope',
      'attempts': 5
    });
    // make firestore throw permission-denied by not seeding doc? fake will not throw — force via unknown type handling?
    // inject op that will throw UnsupportedError
    await OfflineCacheService()
        .queueOperation({'opId': 'x', 'type': 'unknownType', 'attempts': 5});
    await OfflineSyncService().syncPendingOperations();
    expect(
        OfflineCacheService()
            .getFailedOperations()
            .any((o) => o['opId'] == 'x'),
        isTrue);
  });
}
