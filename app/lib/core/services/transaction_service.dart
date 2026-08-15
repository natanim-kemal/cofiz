import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/transaction_model.dart';
import 'worker_service.dart';
import 'notification_trigger_service.dart';
import '../config/cloudinary_config.dart';
import '../utils/receipt_image_utils.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class TransactionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final WorkerService _workerService = WorkerService();
  final NotificationTriggerService _notificationService =
      NotificationTriggerService();
  static const String _transactionsCollection = 'transactions';

  /// Get transactions for a specific worker
  Stream<List<MoneyTransaction>> getWorkerTransactionsStream(String workerId) {
    return _firestore
        .collection(_transactionsCollection)
        .where('workerId', isEqualTo: workerId)
        .snapshots()
        .map((snapshot) {
      final transactions = snapshot.docs.map((doc) {
        return MoneyTransaction.fromFirestore(doc.data(), doc.id);
      }).toList();

      // Sort by date (newest first)
      transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return transactions;
    });
  }

  /// Get all transactions
  Stream<List<MoneyTransaction>> getAllTransactionsStream() {
    return _firestore
        .collection(_transactionsCollection)
        .snapshots()
        .map((snapshot) {
      final transactions = snapshot.docs.map((doc) {
        return MoneyTransaction.fromFirestore(doc.data(), doc.id);
      }).toList();

      // Sort by date (newest first)
      transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return transactions;
    });
  }

  /// Get all transactions (One-time fetch)
  Future<List<MoneyTransaction>> getAllTransactions() async {
    try {
      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => MoneyTransaction.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('Error fetching all transactions: $e');
      return [];
    }
  }

  /// Add transaction and update worker balance
  Future<String?> addTransaction(MoneyTransaction transaction) async {    try {
      // For purchase and return transactions, validate balance first
      if (transaction.type.toLowerCase() == 'purchase' ||
          transaction.type.toLowerCase() == 'return') {
        final workerDoc = await _firestore
            .collection('workers')
            .doc(transaction.workerId)
            .get();

        if (!workerDoc.exists) {
          throw 'Collector not found';
        }

        final currentBalance =
            (workerDoc.data()?['currentBalance'] ?? 0.0).toDouble();

        if (transaction.amount > currentBalance) {
          throw 'Insufficient balance. Available: ETB ${currentBalance.toStringAsFixed(2)}, Required: ETB ${transaction.amount.toStringAsFixed(2)}';
        }
      }

      // Start a batch write
      final batch = _firestore.batch();

      // Add transaction
      final transactionRef =
          _firestore.collection(_transactionsCollection).doc();
      batch.set(transactionRef, transaction.toFirestore());

      // Update worker balance
      final workerRef =
          _firestore.collection('workers').doc(transaction.workerId);

      // Calculate balance change
      double balanceChange = 0;
      Map<String, dynamic> updates = {};

      switch (transaction.type.toLowerCase()) {
        case 'distribution':
          balanceChange = transaction.amount;
          updates = {
            'currentBalance': FieldValue.increment(transaction.amount),
            'totalDistributed': FieldValue.increment(transaction.amount),
            'lastActiveAt': DateTime.now().millisecondsSinceEpoch,
          };
          break;
        case 'return':
          balanceChange = -transaction.amount;
          updates = {
            'currentBalance': FieldValue.increment(-transaction.amount),
            'totalReturned': FieldValue.increment(transaction.amount),
            'lastActiveAt': DateTime.now().millisecondsSinceEpoch,
          };
          break;
        case 'purchase':
          balanceChange = -transaction.amount;
          updates = {
            'currentBalance': FieldValue.increment(-transaction.amount),
            'totalCoffeePurchased': FieldValue.increment(transaction.amount),
            'lastActiveAt': DateTime.now().millisecondsSinceEpoch,
          };
          // Also update totalCommissionEarned if commission was calculated
          if (transaction.commissionAmount != null &&
              transaction.commissionAmount! > 0) {
            updates['totalCommissionEarned'] =
                FieldValue.increment(transaction.commissionAmount!);
          }
          break;
      }

      batch.update(workerRef, updates);

      // Commit the batch
      await batch.commit();

      // Trigger notifications after successful transaction
      await _triggerTransactionNotifications(
        transaction: transaction,
        balanceChange: balanceChange,
      );

      print('Transaction added successfully: ${transactionRef.id}');
      return transactionRef.id;
    } on FirebaseException catch (e) {
      print('Firestore error adding transaction: ${e.code} - ${e.message}');
      throw _handleFirestoreError(e);
    } catch (e) {
      print('Error adding transaction: $e');
      throw 'Failed to add transaction. Please try again.';
    }
  }

  /// Approve a single transaction entry
  Future<void> approveTransaction(String transactionId) async {
    try {
      await _firestore
          .collection(_transactionsCollection)
          .doc(transactionId)
          .update({'approved': true});
    } on FirebaseException catch (e) {
      print('Firestore error approving transaction: ${e.code} - ${e.message}');
      throw _handleFirestoreError(e);
    } catch (e) {
      print('Error approving transaction: $e');
      throw 'Failed to approve transaction. Please try again.';
    }
  }

  /// Batch approve all pending transactions for a worker
  Future<void> approveAllForWorker(String workerId) async {
    try {
      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .where('workerId', isEqualTo: workerId)
          .where('approved', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'approved': true});
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      print('Firestore error batch approving: ${e.code} - ${e.message}');
      throw _handleFirestoreError(e);
    } catch (e) {
      print('Error batch approving: $e');
      throw 'Failed to approve transactions. Please try again.';
    }
  }

  /// Edit an existing transaction, reversing the old balance effect and applying the new one
  Future<void> updateTransaction(MoneyTransaction transaction) async {
    try {
      final doc = await _firestore
          .collection(_transactionsCollection)
          .doc(transaction.id)
          .get();

      if (!doc.exists) {
        throw 'Transaction not found';
      }

      final old = MoneyTransaction.fromFirestore(doc.data()!, transaction.id);

      // Validate balance for money-out types, accounting for the reversed old effect
      if (transaction.type.toLowerCase() == 'purchase' ||
          transaction.type.toLowerCase() == 'return') {
        final workerDoc = await _firestore
            .collection('workers')
            .doc(transaction.workerId)
            .get();

        if (!workerDoc.exists) {
          throw 'Collector not found';
        }

        final currentBalance =
            (workerDoc.data()?['currentBalance'] ?? 0.0).toDouble();

        // Reversing the old transaction: money-out adds back, money-in subtracts
        final oldDirection = old.type.toLowerCase() == 'distribution' ? 1.0 : -1.0;
        final projectedBalance =
            currentBalance + oldDirection * old.amount - transaction.amount;
        if (projectedBalance < 0) {
          throw 'Insufficient balance. Available: ETB ${projectedBalance.toStringAsFixed(2)}, Required: ETB ${transaction.amount.toStringAsFixed(2)}';
        }
      }

      final batch = _firestore.batch();

      final workerRef = _firestore
          .collection('workers')
          .doc(transaction.workerId);

      final oldUpdates = _balanceUpdates(old, -1);
      if (oldUpdates.isNotEmpty) {
        batch.update(workerRef, oldUpdates);
      }

      final newUpdates = _balanceUpdates(transaction, 1);
      if (newUpdates.isNotEmpty) {
        batch.update(workerRef, newUpdates);
      }

      batch.update(
        _firestore.collection(_transactionsCollection).doc(transaction.id),
        transaction.toFirestore(),
      );

      await batch.commit();
      print('Transaction updated successfully: ${transaction.id}');
    } on FirebaseException catch (e) {
      print('Firestore error updating transaction: ${e.code} - ${e.message}');
      throw _handleFirestoreError(e);
    } catch (e) {
      print('Error updating transaction: $e');
      throw 'Failed to update transaction. Please try again.';
    }
  }

  /// Delete an existing transaction, reversing its balance effect
  Future<void> deleteTransaction(String transactionId) async {
    try {
      final doc = await _firestore
          .collection(_transactionsCollection)
          .doc(transactionId)
          .get();

      if (!doc.exists) {
        throw 'Transaction not found';
      }

      final transaction =
          MoneyTransaction.fromFirestore(doc.data()!, transactionId);

      // Reversing a distribution removes money from the balance - validate it
      if (transaction.type.toLowerCase() == 'distribution') {
        final workerDoc = await _firestore
            .collection('workers')
            .doc(transaction.workerId)
            .get();

        if (!workerDoc.exists) {
          throw 'Collector not found';
        }

        final currentBalance =
            (workerDoc.data()?['currentBalance'] ?? 0.0).toDouble();
        if (transaction.amount > currentBalance) {
          throw 'Insufficient balance. Available: ETB ${currentBalance.toStringAsFixed(2)}, Required: ETB ${transaction.amount.toStringAsFixed(2)}';
        }
      }

      final batch = _firestore.batch();

      final workerRef = _firestore
          .collection('workers')
          .doc(transaction.workerId);

      final updates = _balanceUpdates(transaction, -1);
      if (updates.isNotEmpty) {
        batch.update(workerRef, updates);
      }

      batch.delete(
        _firestore.collection(_transactionsCollection).doc(transactionId),
      );

      await batch.commit();
      print('Transaction deleted successfully: $transactionId');
    } on FirebaseException catch (e) {
      print('Firestore error deleting transaction: ${e.code} - ${e.message}');
      throw _handleFirestoreError(e);
    } catch (e) {
      print('Error deleting transaction: $e');
      throw 'Failed to delete transaction. Please try again.';
    }
  }

  Map<String, dynamic> _balanceUpdates(MoneyTransaction t, int direction) {
    final mult = direction.toDouble();
    switch (t.type.toLowerCase()) {
      case 'distribution':
        return {
          'currentBalance': FieldValue.increment(t.amount * mult),
          'totalDistributed': FieldValue.increment(t.amount * mult),
        };
      case 'return':
        return {
          'currentBalance': FieldValue.increment(-t.amount * mult),
          'totalReturned': FieldValue.increment(t.amount * mult),
        };
      case 'purchase':
        final updates = <String, dynamic>{
          'currentBalance': FieldValue.increment(-t.amount * mult),
          'totalCoffeePurchased': FieldValue.increment(t.amount * mult),
        };
        if (t.commissionAmount != null && t.commissionAmount! > 0) {
          updates['totalCommissionEarned'] =
              FieldValue.increment(t.commissionAmount! * mult);
        }
        return updates;
      default:
        return {};
    }
  }

  /// Trigger notifications based on transaction type
  Future<void> _triggerTransactionNotifications({    required MoneyTransaction transaction,
    required double balanceChange,
  }) async {
    try {
      // Get worker data to check userId and new balance
      final workerDoc = await _firestore
          .collection('workers')
          .doc(transaction.workerId)
          .get();

      if (!workerDoc.exists) return;

      final workerData = workerDoc.data()!;
      final workerUserId = workerData['userId'] as String?;
      final workerName = workerData['name'] as String? ?? 'Collector';
      final newBalance = (workerData['currentBalance'] ?? 0.0).toDouble();
      final totalCommission =
          (workerData['totalCommissionEarned'] ?? 0.0).toDouble();

      // Only send notifications if worker has a user account
      if (workerUserId == null || workerUserId.isEmpty) return;

      switch (transaction.type.toLowerCase()) {
        case 'distribution':
          // Notify worker they received money
          await _notificationService.notifyMoneyDistributed(
            workerId: transaction.workerId,
            workerUserId: workerUserId,
            workerName: workerName,
            amount: transaction.amount,
            adminName: null,
          );
          break;

        case 'purchase':
          // Check for low balance
          await _notificationService.checkLowBalance(
            workerId: transaction.workerId,
            workerUserId: workerUserId,
            workerName: workerName,
            newBalance: newBalance,
          );

          // Notify commission earned
          if (transaction.commissionAmount != null &&
              transaction.commissionAmount! > 0) {
            await _notificationService.notifyCommissionEarned(
              workerUserId: workerUserId,
              workerName: workerName,
              commission: transaction.commissionAmount!,
              totalCommission: totalCommission,
            );
          }

          // Check for large purchase (notify admins)
          await _notificationService.checkLargePurchase(
            workerId: transaction.workerId,
            workerName: workerName,
            amount: transaction.amount,
            coffeeType: transaction.coffeeType,
            weight: transaction.coffeeWeight,
          );
          break;

        case 'return':
          // Could add notification for returns if needed
          break;
      }
    } catch (e) {
      // Don't fail the transaction if notification fails
      print('Error triggering notifications: $e');
    }
  }

  /// Get recent transactions (limit)
  Future<List<MoneyTransaction>> getRecentTransactions({int limit = 10}) async {
    try {
      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .limit(limit)
          .get();

      final transactions = snapshot.docs
          .map((doc) => MoneyTransaction.fromFirestore(doc.data(), doc.id))
          .toList();

      transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return transactions;
    } catch (e) {
      print('Error getting recent transactions: $e');
      return [];
    }
  }

  /// Get worker transactions (limit)
  Future<List<MoneyTransaction>> getWorkerTransactions(
    String workerId, {
    int limit = 50,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .where('workerId', isEqualTo: workerId)
          .limit(limit)
          .get();

      final transactions = snapshot.docs
          .map((doc) => MoneyTransaction.fromFirestore(doc.data(), doc.id))
          .toList();

      transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return transactions;
    } catch (e) {
      print('Error getting worker transactions: $e');
      return [];
    }
  }

  /// Get transactions by type
  Future<List<MoneyTransaction>> getTransactionsByType(String type) async {
    try {
      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .where('type', isEqualTo: type)
          .get();

      final transactions = snapshot.docs
          .map((doc) => MoneyTransaction.fromFirestore(doc.data(), doc.id))
          .toList();

      transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return transactions;
    } catch (e) {
      print('Error getting transactions by type: $e');
      return [];
    }
  }

  /// Calculate total for today
  Future<Map<String, double>> getTodayTotals() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final startTimestamp = startOfDay.millisecondsSinceEpoch;

      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .where('createdAt', isGreaterThanOrEqualTo: startTimestamp)
          .get();

      double totalDistributed = 0;
      double totalReturned = 0;
      double totalPurchased = 0;

      for (var doc in snapshot.docs) {
        final transaction = MoneyTransaction.fromFirestore(doc.data(), doc.id);
        switch (transaction.type.toLowerCase()) {
          case 'distribution':
            totalDistributed += transaction.amount;
            break;
          case 'return':
            totalReturned += transaction.amount;
            break;
          case 'purchase':
            totalPurchased += transaction.amount;
            break;
        }
      }

      return {
        'distributed': totalDistributed,
        'returned': totalReturned,
        'purchased': totalPurchased,
      };
    } catch (e) {
      print('Error getting today totals: $e');
      return {
        'distributed': 0.0,
        'returned': 0.0,
        'purchased': 0.0,
      };
    }
  }

  /// Handle Firestore exceptions with user-friendly messages
  String _handleFirestoreError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Database access denied. Please check your permissions.';
      case 'unavailable':
        return 'Database is currently unavailable. Please check your internet connection.';
      case 'not-found':
        return 'Transaction not found in database.';
      case 'already-exists':
        return 'This transaction already exists.';
      default:
        return 'Database error: ${e.message ?? 'Unknown error'}';
    }
  }

  Future<String?> uploadReceipt(String filePath) async {
    try {
      final compressedBytes = await ReceiptImageUtils.compress(filePath);
      if (compressedBytes == null || compressedBytes.isEmpty) return null;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(CloudinaryConfig.uploadEndpoint),
      )
        ..fields['upload_preset'] = CloudinaryConfig.uploadPreset
        ..fields['folder'] = CloudinaryConfig.folder
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          compressedBytes,
          filename: 'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        print(
          'Cloudinary upload failed (${response.statusCode}): ${response.body}',
        );
        throw 'Failed to upload receipt image';
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final secureUrl = json['secure_url'] as String?;
      return secureUrl;
    } catch (e) {
      print('Error uploading receipt: $e');
      throw 'Failed to upload receipt image';
    }
  }
}
