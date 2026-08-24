import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/user_model.dart';

void main() {
  test('viewer cannot create transactions', () {
    expect(UserRole.viewer.canCreateTransactions, isFalse);
  });

  test('admin can create transactions', () {
    expect(UserRole.admin.canCreateTransactions, isTrue);
  });

  test('worker can create transactions', () {
    expect(UserRole.worker.canCreateTransactions, isTrue);
  });
}
