import 'package:cloud_firestore/cloud_firestore.dart';

class AreaService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Default areas that cannot be edited/deleted by workers
  static const List<String> defaultAreas = [
    "Bo'e",
    'Ebicha',
    'Jirmtiti',
    'Bogema',
    'Guduba-luka',
    'Haru-fora',
    'Awata',
    'Tulise',
  ];

  /// Check if an area is a default area
  bool isDefaultArea(String areaName) {
    return defaultAreas.contains(areaName);
  }

  /// Get all areas (sorted alphabetically)
  Stream<List<String>> getAreasStream() {
    return _firestore
        .collection('settings')
        .doc('areas')
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) {
        return <String>[];
      }
      final data = doc.data()!;
      final List<dynamic> areas = data['areas'] ?? [];
      return areas.cast<String>()..sort();
    });
  }

  /// Get areas list (one-time fetch)
  Future<List<String>> getAreas() async {
    final doc = await _firestore.collection('settings').doc('areas').get();
    if (!doc.exists || doc.data() == null) {
      return [];
    }
    final List<dynamic> areas = doc.data()!['areas'] ?? [];
    return areas.cast<String>()..sort();
  }

  /// Add a new area
  Future<void> addArea(String areaName) async {
    final trimmed = areaName.trim();
    if (trimmed.isEmpty) return;

    await _firestore.collection('settings').doc('areas').set({
      'areas': FieldValue.arrayUnion([trimmed]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Remove an area (workers can only remove non-default areas)
  Future<void> removeArea(String areaName) async {
    await _firestore.collection('settings').doc('areas').update({
      'areas': FieldValue.arrayRemove([areaName]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update an area name
  Future<void> updateArea(String oldName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || oldName == trimmed) return;

    // Get current areas
    final areas = await getAreas();
    final index = areas.indexOf(oldName);
    if (index != -1) {
      areas[index] = trimmed;
      await _firestore.collection('settings').doc('areas').set({
        'areas': areas,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Initialize default areas if none exist
  Future<void> initializeDefaultAreas() async {
    final doc = await _firestore.collection('settings').doc('areas').get();
    if (!doc.exists) {
      await _firestore.collection('settings').doc('areas').set({
        'areas': defaultAreas,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
