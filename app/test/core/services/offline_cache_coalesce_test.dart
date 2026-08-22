import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('coalesce');
    await OfflineCacheService().initialize(path: dir.path);
  });
  tearDown(() async => await OfflineCacheService().clearAllCache());
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('create+delete same id drops both', () async {
    final svc = OfflineCacheService();
    await svc.queueOperation({
      'opId': 'a',
      'type': 'createIncome',
      'docId': 'a',
      'payload': {'amount': 10},
      'attempts': 0
    });
    await svc.queueOperation(
        {'opId': 'a', 'type': 'deleteIncome', 'docId': 'a', 'attempts': 0});
    expect(svc.getPendingOperations().where((o) => o['opId'] == 'a'), isEmpty);
  });
  test('create+update merges into create with final payload', () async {
    final svc = OfflineCacheService();
    await svc.queueOperation({
      'opId': 'b',
      'type': 'createIncome',
      'docId': 'b',
      'payload': {'amount': 10},
      'attempts': 0
    });
    await svc.queueOperation({
      'opId': 'b',
      'type': 'updateIncome',
      'docId': 'b',
      'payload': {'amount': 20},
      'attempts': 0
    });
    final ops =
        svc.getPendingOperations().where((o) => o['opId'] == 'b').toList();
    expect(ops.length, 1);
    expect(ops[0]['type'], 'createIncome');
    expect(ops[0]['payload']['amount'], 20);
  });
  test('update+update keeps last', () async {
    final svc = OfflineCacheService();
    await svc.queueOperation({
      'opId': 'c',
      'type': 'updateIncome',
      'docId': 'c',
      'payload': {'amount': 10},
      'attempts': 0
    });
    await svc.queueOperation({
      'opId': 'c',
      'type': 'updateIncome',
      'docId': 'c',
      'payload': {'amount': 30},
      'attempts': 0
    });
    expect(svc.getPendingOperations().where((o) => o['opId'] == 'c').length, 1);
    expect(
        svc
            .getPendingOperations()
            .firstWhere((o) => o['opId'] == 'c')['payload']['amount'],
        30);
  });
  test('update+delete keeps delete', () async {
    final svc = OfflineCacheService();
    await svc.queueOperation({
      'opId': 'd',
      'type': 'updateIncome',
      'docId': 'd',
      'payload': {'amount': 10},
      'attempts': 0
    });
    await svc.queueOperation(
        {'opId': 'd', 'type': 'deleteIncome', 'docId': 'd', 'attempts': 0});
    final ops =
        svc.getPendingOperations().where((o) => o['opId'] == 'd').toList();
    expect(ops.length, 1);
    expect(ops[0]['type'], 'deleteIncome');
  });
  test('delete+create keeps both in order', () async {
    final svc = OfflineCacheService();
    await svc.queueOperation(
        {'opId': 'e', 'type': 'deleteIncome', 'docId': 'e', 'attempts': 0});
    await svc.queueOperation({
      'opId': 'e',
      'type': 'createIncome',
      'docId': 'e',
      'payload': {'amount': 99},
      'attempts': 0
    });
    final ops =
        svc.getPendingOperations().where((o) => o['opId'] == 'e').toList();
    expect(ops.length, 2);
    expect(ops[0]['type'], 'deleteIncome');
    expect(ops[1]['type'], 'createIncome');
  });
  test('transfer coalesce by transferId', () async {
    final svc = OfflineCacheService();
    // Queue createTransfer with opId t1 and transferId t1
    await svc.queueOperation({
      'opId': 't1',
      'transferId': 't1',
      'type': 'createTransfer',
      'docId': 't1',
      'payload': {'amount': 50},
      'attempts': 0
    });
    // Second op uses different opId but same transferId -> should coalesce
    // via transferId fallback (create+delete drop)
    await svc.queueOperation({
      'opId': 't1b',
      'transferId': 't1',
      'type': 'deleteTransfer',
      'docId': 't1',
      'attempts': 0
    });
    final ops = svc.getPendingOperations();
    // Both should be dropped via create+delete coalescence on transferId
    expect(
        ops.where((o) => (o['transferId'] == 't1' ||
            o['opId'] == 't1' ||
            o['opId'] == 't1b')),
        isEmpty);
  });
}
