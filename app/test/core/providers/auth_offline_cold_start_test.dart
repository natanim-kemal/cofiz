import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline cold start does not hang - auth uses cache fallback', () async {
    final file = File('lib/core/providers/auth_provider.dart');
    final content = await file.readAsString();
    expect(content.contains('GetOptions(source: Source.server)'), isTrue);
    expect(content.contains('GetOptions(source: Source.cache)'), isTrue);
    expect(content.contains('_loadCachedAppUser'), isTrue);
    expect(content.contains('timeout(const Duration(seconds: 3))'), isTrue);
    expect(content.contains('_cacheAppUser'), isTrue);
  });

  test('signOut preserves outbox has keepOutbox param', () async {
    final cacheFile = File('lib/core/services/offline_cache_service.dart');
    final cacheContent = await cacheFile.readAsString();
    expect(cacheContent.contains('keepOutbox'), isTrue);

    final authFile = File('lib/core/providers/auth_provider.dart');
    final authContent = await authFile.readAsString();
    expect(authContent.contains('clearAllCache(keepOutbox: true)'), isTrue);
  });
}
