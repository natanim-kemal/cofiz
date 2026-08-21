import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cofiz/core/models/worker_model.dart';
import 'package:cofiz/core/providers/worker_provider.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/worker_service.dart';

void main() {
  late Directory tempDir;

  Worker worker(String id) => Worker(
        id: id,
        name: 'Alice $id',
        phone: '0911',
        role: 'Worker',
        status: 'active',
        createdAt: DateTime(2026, 8, 1),
        currentBalance: 250,
      );

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('worker_profile_cache');
    await OfflineCacheService().initialize(path: tempDir.path);
  });

  setUp(() async {
    await OfflineCacheService().clearAllCache();
  });

  tearDownAll(() async {
    await OfflineCacheService().clearAllCache();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('getCachedWorkerById returns cached profile synchronously', () async {
    await OfflineCacheService().cacheWorkerProfile(worker('w1'));

    final provider = WorkerProvider(
      service: WorkerService(firestore: FakeFirebaseFirestore()),
    );

    final cached = provider.getCachedWorkerById('w1');
    expect(cached, isNotNull);
    expect(cached!.name, 'Alice w1');
  });

  test('getWorkerById falls back to cache when the network has no data',
      () async {
    await OfflineCacheService().cacheWorkerProfile(worker('w1'));

    // Empty Firestore - getWorkerById resolves null, provider must fall
    // back to the cached profile instead of returning null.
    final provider = WorkerProvider(
      service: WorkerService(firestore: FakeFirebaseFirestore()),
    );

    final result = await provider.getWorkerById('w1');
    expect(result, isNotNull);
    expect(result!.id, 'w1');
    expect(result.currentBalance, 250);
  });

  test('successful network fetch updates the Hive profile cache', () async {
    final fake = FakeFirebaseFirestore();
    await fake.collection('workers').doc('w2').set(worker('w2').toFirestore());

    final provider = WorkerProvider(service: WorkerService(firestore: fake));

    expect(OfflineCacheService().getCachedWorkerProfile(expectedId: 'w2'),
        isNull);

    final result = await provider.getWorkerById('w2');

    expect(result, isNotNull);
    expect(result!.name, 'Alice w2');
    final nowCached =
        OfflineCacheService().getCachedWorkerProfile(expectedId: 'w2');
    expect(nowCached, isNotNull);
    expect(nowCached!.currentBalance, 250);
  });
}
