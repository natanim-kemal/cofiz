import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/services/auth_backend_firebase.dart';

void main() {
  test('AuthBackendFirebase is constructible', () {
    final s = AuthBackendFirebase();
    expect(s, isNotNull);
  });
}
