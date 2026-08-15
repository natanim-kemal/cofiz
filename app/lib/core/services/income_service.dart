import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/income_record_model.dart';

class IncomeService {
  static const String _collectionName = 'income_records';
  static const String _settingsDoc = 'saleCategories';
  static const String _settingsCollection = 'settings';

  static const List<String> defaultSaleCategories = [
    'Coffee Beans',
    'Processed Coffee',
    'Equipment',
    'Byproducts',
    'Other',
  ];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _categoriesRef =>
      _firestore.collection(_settingsCollection).doc(_settingsDoc);

  Stream<List<IncomeRecord>> getIncomeStream() {
    return _firestore
        .collection(_collectionName)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => IncomeRecord.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  Stream<List<IncomeRecord>> getIncomeForViewerStream(String viewerId) {
    return _firestore
        .collection(_collectionName)
        .where('viewerId', isEqualTo: viewerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => IncomeRecord.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  Future<String?> addIncome(IncomeRecord record) async {
    try {
      final docRef = await _firestore
          .collection(_collectionName)
          .add(record.toFirestore());
      return docRef.id;
    } catch (e) {
      print('Error adding income: $e');
      return null;
    }
  }

  Future<bool> updateIncome(IncomeRecord record) async {
    try {
      await _firestore
          .collection(_collectionName)
          .doc(record.id)
          .update(record.toFirestore());
      return true;
    } catch (e) {
      print('Error updating income: $e');
      return false;
    }
  }

  Future<bool> deleteIncome(String id) async {
    try {
      await _firestore.collection(_collectionName).doc(id).delete();
      return true;
    } catch (e) {
      print('Error deleting income: $e');
      return false;
    }
  }

  Future<void> initializeDefaultSaleCategories() async {
    try {
      final snap = await _categoriesRef.get();
      final categories = (snap.data()?['categories'] as List?)?.cast<String>();
      if (categories == null || categories.isEmpty) {
        await _categoriesRef.set({'categories': defaultSaleCategories});
      }
    } catch (e) {
      print('Error initializing sale categories: $e');
    }
  }

  Stream<List<String>> getSaleCategoriesStream() {
    return _categoriesRef.snapshots().map((snap) {
      final categories = (snap.data()?['categories'] as List?)?.cast<String>();
      if (categories == null || categories.isEmpty) {
        return defaultSaleCategories;
      }
      return categories;
    });
  }

  Future<List<String>> getSaleCategories() async {
    try {
      final snap = await _categoriesRef.get();
      final categories = (snap.data()?['categories'] as List?)?.cast<String>();
      if (categories == null || categories.isEmpty) {
        return defaultSaleCategories;
      }
      return categories;
    } catch (e) {
      return defaultSaleCategories;
    }
  }

  Future<bool> addSaleCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    try {
      final current = await getSaleCategories();
      if (current.contains(trimmed)) return true;
      await _categoriesRef.update({
        'categories': FieldValue.arrayUnion([trimmed]),
      });
      return true;
    } catch (e) {
      print('Error adding sale category: $e');
      return false;
    }
  }

  Future<bool> removeSaleCategory(String name) async {
    if (defaultSaleCategories.contains(name)) return false;
    try {
      await _categoriesRef.update({
        'categories': FieldValue.arrayRemove([name]),
      });
      return true;
    } catch (e) {
      print('Error removing sale category: $e');
      return false;
    }
  }
}
