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
}
