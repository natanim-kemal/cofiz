import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../utils/password_generator.dart';

class WorkerAccountService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Secondary Firebase app for creating accounts without affecting current session
  static FirebaseApp? _secondaryApp;
  static FirebaseAuth? _secondaryAuth;

  /// Initialize secondary Firebase app for account creation
  Future<void> _initSecondaryApp() async {
    if (_secondaryApp == null) {
      try {
        // Check if the secondary app already exists
        _secondaryApp = Firebase.app('workerCreation');
      } catch (e) {
        // Create a new secondary app
        _secondaryApp = await Firebase.initializeApp(
          name: 'workerCreation',
          options: Firebase.app().options,
        );
      }
      _secondaryAuth = FirebaseAuth.instanceFor(app: _secondaryApp!);
    }
  }

  /// Create worker account (auth + user document)
  Future<Map<String, dynamic>> createWorkerAccount({
    required String workerId,
    required String email,
    required String workerName,
  }) async {
    try {
      // Initialize secondary app to avoid signing out admin
      await _initSecondaryApp();

      final password = PasswordGenerator.generate(length: 8);

      // Create Firebase Auth account using secondary app (doesn't affect main session)
      final UserCredential userCredential =
          await _secondaryAuth!.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final userId = userCredential.user!.uid;

      // Sign out from secondary app immediately
      await _secondaryAuth!.signOut();

      // Create user document in Firestore with 'worker' role
      final appUser = AppUser(
        uid: userId,
        email: email,
        displayName: workerName,
        role: UserRole.worker, // Workers get 'worker' role
        workerId: workerId,
        createdAt: DateTime.now(),
        isActive: true,
      );

      await _firestore
          .collection('users')
          .doc(userId)
          .set(appUser.toFirestore());

      // Update worker document with userId
      await _firestore.collection('workers').doc(workerId).update({
        'userId': userId,
        'hasLoginAccess': true,
      });

      return {
        'success': true,
        'password': password,
        'userId': userId,
        'requiresReauth': false, // Admin stays logged in!
      };
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Failed to create account';

      switch (e.code) {
        case 'email-already-in-use':
          // Attempt to restore access if worker already has this account linked
          try {
            final workerDoc =
                await _firestore.collection('workers').doc(workerId).get();
            final currentUserId = workerDoc.data()?['userId'];
            if (currentUserId != null) {
              await _firestore.collection('workers').doc(workerId).update({
                'hasLoginAccess': true,
              });
              return {
                'success': true,
                'password': 'Existing (Unchanged)',
                'userId': currentUserId,
                'message': 'Login access restored for existing account',
              };
            }
          } catch (_) {}

          errorMessage = 'This email is already in use';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address';
          break;
        case 'weak-password':
          errorMessage = 'Password is too weak';
          break;
        default:
          errorMessage = e.message ?? 'Unknown error occurred';
      }

      return {
        'success': false,
        'error': errorMessage,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'An error occurred: $e',
      };
    }
  }

  Future<void> deleteWorkerAccount(String userId) async {
    try {
      // Delete user document
      await _firestore.collection('users').doc(userId).delete();

      // Note: Cannot delete Firebase Auth user from client side
      // This would require Admin SDK or Cloud Functions
      // For now, just delete Firestore document and set worker hasLoginAccess to false
    } catch (e) {
      print('Error deleting worker account: $e');
    }
  }
}
