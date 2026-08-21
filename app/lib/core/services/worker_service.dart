import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/worker_model.dart';

class WorkerService {
  final FirebaseFirestore _firestore;
  static const String _workersCollection = 'workers';

  WorkerService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Get all workers stream
  Stream<List<Worker>> getWorkersStream() {
    return _firestore
        .collection(_workersCollection)
        .where('isActive', isEqualTo: true)
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Worker.fromFirestore(doc.data(), doc.id);
      }).toList();
    });
  }

  /// Get workers by status
  Stream<List<Worker>> getWorkersByStatus(String status) {
    return _firestore
        .collection(_workersCollection)
        .where('isActive', isEqualTo: true)
        .where('status', isEqualTo: status.toLowerCase())
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Worker.fromFirestore(doc.data(), doc.id);
      }).toList();
    });
  }

  /// Get single worker by ID
  Future<Worker?> getWorkerById(String id) async {
    try {
      final doc = await _firestore.collection(_workersCollection).doc(id).get();
      if (doc.exists && doc.data() != null) {
        return Worker.fromFirestore(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      print('Error getting worker: $e');
      return null;
    }
  }

  /// Add new worker
  Future<String?> addWorker(Worker worker) async {
    try {
      final docRef = await _firestore
          .collection(_workersCollection)
          .add(worker.toFirestore());
      return docRef.id;
    } on FirebaseException catch (e) {
      print('Firestore error adding worker: ${e.code} - ${e.message}');
      throw _handleFirestoreError(e);
    } catch (e) {
      print('Error adding worker: $e');
      throw 'Failed to add collector. Please try again.';
    }
  }

  /// Update worker
  Future<void> updateWorker(String id, Worker worker) async {
    try {
      await _firestore
          .collection(_workersCollection)
          .doc(id)
          .update(worker.toFirestore());
    } on FirebaseException catch (e) {
      print('Firestore error updating worker: ${e.code} - ${e.message}');
      throw _handleFirestoreError(e);
    } catch (e) {
      print('Error updating worker: $e');
      throw 'Failed to update collector. Please try again.';
    }
  }

  /// Delete worker (soft delete)
  Future<void> deleteWorker(String id) async {
    try {
      await _firestore.collection(_workersCollection).doc(id).update({
        'isActive': false,
      });
    } on FirebaseException catch (e) {
      print('Firestore error deleting worker: ${e.code} - ${e.message}');
      throw _handleFirestoreError(e);
    } catch (e) {
      print('Error deleting worker: $e');
      throw 'Failed to delete collector. Please try again.';
    }
  }

  /// Handle Firestore exceptions with user-friendly messages
  String _handleFirestoreError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Database access denied. Please check your permissions or enable Firestore.';
      case 'unavailable':
        return 'Database is currently unavailable. Please check your internet connection.';
      case 'not-found':
        return 'Collector not found in database.';
      case 'already-exists':
        return 'This collector already exists.';
      case 'resource-exhausted':
        return 'Too many requests. Please try again later.';
      case 'unauthenticated':
        return 'You must be signed in to perform this action.';
      case 'deadline-exceeded':
        return 'Request timed out. Please try again.';
      default:
        return 'Database error: ${e.message ?? 'Unknown error'}';
    }
  }

  /// Update worker status
  Future<void> updateWorkerStatus(String id, String status) async {
    try {
      await _firestore.collection(_workersCollection).doc(id).update({
        'status': status.toLowerCase(),
        'lastActiveAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('Error updating worker status: $e');
      throw 'Failed to update collector status: $e';
    }
  }

  /// Update worker balance
  Future<void> updateWorkerBalance(
    String id,
    double amount, {
    required String type, // 'distribute', 'return', 'purchase'
  }) async {
    try {
      final worker = await getWorkerById(id);
      if (worker == null) throw 'Collector not found';

      double newBalance = worker.currentBalance;
      double newTotalDistributed = worker.totalDistributed;
      double newTotalReturned = worker.totalReturned;
      double newTotalCoffeePurchased = worker.totalCoffeePurchased;

      switch (type) {
        case 'distribute':
          newBalance += amount;
          newTotalDistributed += amount;
          break;
        case 'return':
          newBalance -= amount;
          newTotalReturned += amount;
          break;
        case 'purchase':
          newBalance -= amount;
          newTotalCoffeePurchased += amount;
          break;
      }

      await _firestore.collection(_workersCollection).doc(id).update({
        'currentBalance': newBalance,
        'totalDistributed': newTotalDistributed,
        'totalReturned': newTotalReturned,
        'totalCoffeePurchased': newTotalCoffeePurchased,
      });
    } catch (e) {
      print('Error updating worker balance: $e');
      throw 'Failed to update collector balance: $e';
    }
  }

  /// Get statistics
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final snapshot = await _firestore
          .collection(_workersCollection)
          .where('isActive', isEqualTo: true)
          .get();

      final workers = snapshot.docs
          .map((doc) => Worker.fromFirestore(doc.data(), doc.id))
          .toList();

      final totalWorkers = workers.length;
      final activeToday = workers.where((w) => w.status == 'active').length;

      final totalRevenue = workers.fold<double>(
        0.0,
        (sum, worker) => sum + worker.totalCoffeePurchased,
      );

      final avgPerformance = workers.isNotEmpty
          ? workers.fold<double>(
                  0.0, (sum, worker) => sum + worker.performanceRating) /
              workers.length
          : 0.0;

      return {
        'totalWorkers': totalWorkers,
        'activeToday': activeToday,
        'totalRevenue': totalRevenue,
        'avgPerformance': avgPerformance,
      };
    } catch (e) {
      print('Error getting statistics: $e');
      return {
        'totalWorkers': 0,
        'activeToday': 0,
        'totalRevenue': 0.0,
        'avgPerformance': 0.0,
      };
    }
  }

  /// Search workers by name
  Future<List<Worker>> searchWorkers(String query) async {
    try {
      if (query.isEmpty) {
        final snapshot = await _firestore
            .collection(_workersCollection)
            .where('isActive', isEqualTo: true)
            .orderBy('name')
            .get();

        return snapshot.docs
            .map((doc) => Worker.fromFirestore(doc.data(), doc.id))
            .toList();
      }

      // Firestore doesn't support case-insensitive search or contains
      // So we fetch all and filter locally
      final snapshot = await _firestore
          .collection(_workersCollection)
          .where('isActive', isEqualTo: true)
          .get();

      final workers = snapshot.docs
          .map((doc) => Worker.fromFirestore(doc.data(), doc.id))
          .toList();

      return workers
          .where((worker) =>
              worker.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
    } catch (e) {
      print('Error searching workers: $e');
      return [];
    }
  }
}
