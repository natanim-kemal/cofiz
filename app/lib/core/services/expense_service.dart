import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/expense_record_model.dart';
import 'offline_cache_service.dart';
import 'offline_sync_service.dart';

/// A single page of expense records from a cursor-paginated query.
class ExpensePage {
  final List<ExpenseRecord> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  ExpensePage({
    required this.items,
    required this.lastDoc,
    required this.hasMore,
  });
}

class ExpenseService {
  static const String _collectionName = 'expenses';
  static const String _settingsDoc = 'expenseCategories';
  static const String _settingsCollection = 'settings';

  static const List<String> defaultExpenseCategories = [
    'Purchased Goods',
    'Salary',
    'Wages',
    'Maintenance',
    'Food',
    'Transport',
    'Rent',
    'Other',
  ];

  final FirebaseFirestore _firestore;

  ExpenseService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _categoriesRef =>
      _firestore.collection(_settingsCollection).doc(_settingsDoc);

  Stream<List<ExpenseRecord>> getExpensesStream() {
    return _firestore
        .collection(_collectionName)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ExpenseRecord.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  /// Bounded live stream of the newest expense records (first page only).
  Stream<List<ExpenseRecord>> getExpensesPageStream({int limit = 20}) {
    return _firestore
        .collection(_collectionName)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ExpenseRecord.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  /// Fetch a page of expense records (newest first) via cursor.
  Future<ExpensePage> getExpensesPage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = 20,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection(_collectionName)
          .orderBy('createdAt', descending: true)
          .limit(pageSize);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      final snapshot = await query.get();
      final records = snapshot.docs
          .map((doc) => ExpenseRecord.fromFirestore(doc.data(), doc.id))
          .toList();
      return ExpensePage(
        items: records,
        lastDoc: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        hasMore: snapshot.docs.length == pageSize,
      );
    } catch (e) {
      print('Error fetching expenses page: $e');
      return ExpensePage(items: const [], lastDoc: null, hasMore: false);
    }
  }

  /// Fetch all expense records for a specific calendar day (newest first).
  Future<List<ExpenseRecord>> getExpensesForDay(DateTime day) async {
    final startOfDay = DateTime(day.year, day.month, day.day);
    final startTimestamp = startOfDay.millisecondsSinceEpoch;
    final endTimestamp =
        startOfDay.add(const Duration(days: 1)).millisecondsSinceEpoch;
    try {
      final snap = await _firestore
          .collection(_collectionName)
          .where('createdAt', isGreaterThanOrEqualTo: startTimestamp)
          .where('createdAt', isLessThan: endTimestamp)
          .orderBy('createdAt', descending: true)
          .get();
      return snap.docs
          .map((doc) => ExpenseRecord.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetch all expense records (newest first) - for reports/export.
  Future<List<ExpenseRecord>> getAllExpenses() async {
    try {
      final snap = await _firestore
          .collection(_collectionName)
          .orderBy('createdAt', descending: true)
          .get();
      return snap.docs
          .map((doc) => ExpenseRecord.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('Error fetching all expense records: $e');
      return const [];
    }
  }

  /// Server-side total expenses sum.
  /// Returns null if the query fails (e.g. index not ready/offline).
  Future<double?> getExpensesTotal() async {
    try {
      final snapshot = await _firestore
          .collection(_collectionName)
          .aggregate(sum('amount'))
          .get();
      return snapshot.getSum('amount') ?? 0.0;
    } catch (e) {
      print('Error fetching expenses total: $e');
      return null;
    }
  }

  /// Server-side total expenses sum for today.
  /// Returns null if the query fails.
  Future<double?> getExpensesTodayTotal() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      final snapshot = await _firestore
          .collection(_collectionName)
          .where('createdAt',
              isGreaterThanOrEqualTo: start.millisecondsSinceEpoch)
          .where('createdAt', isLessThan: end.millisecondsSinceEpoch)
          .aggregate(sum('amount'))
          .get();
      return snapshot.getSum('amount') ?? 0.0;
    } catch (e) {
      print('Error fetching today expenses total: $e');
      return null;
    }
  }

  /// Server-side count of expense records.
  /// Returns null if the query fails.
  Future<int?> getExpensesCount() async {
    try {
      final snapshot =
          await _firestore.collection(_collectionName).count().get();
      return snapshot.count ?? 0;
    } catch (e) {
      print('Error fetching expenses count: $e');
      return null;
    }
  }

  Future<String?> addExpense(ExpenseRecord record) async {
    final opId = const Uuid().v4();
    await OfflineCacheService().queueOperation({
      'opId': opId,
      'type': 'createExpense',
      'docId': opId,
      'payload': record.toFirestore(),
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    final cached = OfflineCacheService().getCachedExpenses() ?? [];
    await OfflineCacheService()
        .cacheExpenses([...cached, record.copyWith(id: opId)]);
    debugPrint('[ExpenseService] addExpense opId=$opId queued+cached, syncing...');
    unawaited(OfflineSyncService().syncNow());
    return opId;
  }

  Future<bool> updateExpense(ExpenseRecord record) async {
    try {
      await _firestore
          .collection(_collectionName)
          .doc(record.id)
          .update(record.toFirestore());
      return true;
    } catch (e) {
      print('Error updating expense: $e');
      return false;
    }
  }

  Future<bool> deleteExpense(String id) async {
    try {
      await _firestore.collection(_collectionName).doc(id).delete();
      debugPrint('[ExpenseService] deleteExpense id=$id OK');
      return true;
    } catch (e) {
      debugPrint('[ExpenseService] deleteExpense id=$id FAILED: $e');
      return false;
    }
  }

  Future<void> initializeDefaultExpenseCategories() async {
    try {
      final snap = await _categoriesRef.get();
      final categories = (snap.data()?['categories'] as List?)?.cast<String>();
      if (categories == null || categories.isEmpty) {
        await _categoriesRef.set({'categories': defaultExpenseCategories});
      }
    } catch (e) {
      print('Error initializing expense categories: $e');
    }
  }

  Stream<List<String>> getExpenseCategoriesStream() {
    return _categoriesRef.snapshots().map((snap) {
      final categories = (snap.data()?['categories'] as List?)?.cast<String>();
      if (categories == null || categories.isEmpty) {
        return defaultExpenseCategories;
      }
      return categories;
    });
  }

  Future<List<String>> getExpenseCategories() async {
    try {
      final snap = await _categoriesRef.get();
      final categories = (snap.data()?['categories'] as List?)?.cast<String>();
      if (categories == null || categories.isEmpty) {
        return defaultExpenseCategories;
      }
      return categories;
    } catch (e) {
      return defaultExpenseCategories;
    }
  }

  Future<bool> addExpenseCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    try {
      final current = await getExpenseCategories();
      if (current.contains(trimmed)) return true;
      await _categoriesRef.update({
        'categories': FieldValue.arrayUnion([trimmed]),
      });
      return true;
    } catch (e) {
      print('Error adding expense category: $e');
      return false;
    }
  }

  Future<bool> removeExpenseCategory(String name) async {
    if (defaultExpenseCategories.contains(name)) return false;
    try {
      await _categoriesRef.update({
        'categories': FieldValue.arrayRemove([name]),
      });
      return true;
    } catch (e) {
      print('Error removing expense category: $e');
      return false;
    }
  }
}
