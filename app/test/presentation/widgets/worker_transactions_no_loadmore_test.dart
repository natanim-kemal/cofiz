import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  test('worker details does not show Load More', () async {
    final file = File('lib/presentation/widgets/worker_transactions_list.dart');
    final content = await file.readAsString();
    expect(content.contains('Load More'), isFalse);
    expect(content.contains('hasMoreWorkerTransactions'), isFalse,
        reason: 'Load More logic should be removed from worker details');
  });
}
