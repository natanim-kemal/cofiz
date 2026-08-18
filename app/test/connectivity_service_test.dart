import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/services/connectivity_service.dart';

void main() {
  test('setOnlineForTest overrides isOnline', () {
    final service = ConnectivityService();
    service.setOnlineForTest(false);
    expect(service.isOnline, isFalse);
    service.setOnlineForTest(true);
    expect(service.isOnline, isTrue);
  });

  test('factory returns the shared singleton', () {
    expect(identical(ConnectivityService(), ConnectivityService()), isTrue);
  });
}
