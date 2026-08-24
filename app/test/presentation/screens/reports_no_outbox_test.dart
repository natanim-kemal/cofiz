import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports screen does not show pending/failed indicator', () async {
    final file = File('lib/presentation/screens/reports/reports_screen.dart');
    final content = await file.readAsString();
    expect(content.contains('SyncOutboxBanner'), isFalse,
        reason: 'Reports screen should not show pending/failed count');
    expect(content.contains('OfflineIndicator'), isTrue,
        reason: 'Reports should still show offline cloud notice');
  });
}
