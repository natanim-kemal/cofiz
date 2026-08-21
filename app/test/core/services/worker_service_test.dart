import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/services/worker_service.dart';

void main() {
  test('getWorkerById returns the stored worker doc', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('workers').doc('w1').set({
      'name': 'Old Name',
      'phone': '0911000000',
      'role': 'Worker',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    final service = WorkerService(firestore: firestore);
    final worker = await service.getWorkerById('w1');

    expect(worker, isNotNull);
    expect(worker!.name, 'Old Name');
  });
}
