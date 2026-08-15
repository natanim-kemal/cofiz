import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense_record_model.dart';

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

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

  Future<String?> addExpense(ExpenseRecord record) async {
    try {
      final docRef = await _firestore
          .collection(_collectionName)
          .add(record.toFirestore());
      return docRef.id;
    } catch (e) {
      print('Error adding expense: $e');
      return null;
    }
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
      return true;
    } catch (e) {
      print('Error deleting expense: $e');
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
