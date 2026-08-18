import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _loginTimestampKey = 'login_timestamp';
  static const int _sessionDurationDays = 7;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Check if user is logged in
  bool get isLoggedIn => _auth.currentUser != null;

  // Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Enable persistence explicitly
  Future<void> enablePersistence() async {
    try {
      await _auth.setPersistence(Persistence.LOCAL);
    } catch (e) {}
  }

  /// Sign in with email and password
  Future<UserCredential?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      await _saveLoginTimestamp();

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Unexpected error: $e';
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      await _clearLoginTimestamp();
    } catch (e) {
      throw 'Failed to sign out. Please try again.';
    }
  }

  /// Check if session is still valid (within 7 days)
  Future<bool> isSessionValid() async {
    if (_auth.currentUser == null) {
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_loginTimestampKey);

      if (timestamp == null) return false;

      final loginDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      final difference = now.difference(loginDate);

      // Session is valid if less than 7 days
      return difference.inDays < _sessionDurationDays;
    } catch (e) {
      return false;
    }
  }

  /// Save login timestamp to SharedPreferences
  Future<void> _saveLoginTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _loginTimestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Clear login timestamp
  Future<void> _clearLoginTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_loginTimestampKey);
  }

  /// Auto logout if session expired
  Future<void> checkAndEnforceSession() async {
    final isValid = await isSessionValid();
    if (!isValid && _auth.currentUser != null) {
      await signOut();
    }
  }

  /// Handle Firebase Auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email address.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-email':
        return 'Invalid email address format.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      default:
        return 'Authentication failed: ${e.message ?? 'Unknown error'}';
    }
  }

  /// Get user email
  String? getUserEmail() {
    return _auth.currentUser?.email;
  }

  /// Get user display name (if set)
  String? getUserDisplayName() {
    return _auth.currentUser?.displayName;
  }

  /// Get user ID
  String? getUserId() {
    return _auth.currentUser?.uid;
  }

  /// Reset password - send reset email
  Future<void> resetPassword({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Failed to send reset email. Please try again.';
    }
  }

  Future<void> updateProfile({String? displayName, String? photoUrl}) async {
    User? user = _auth.currentUser;
    if (user != null) {
      try {
        if (displayName != null) await user.updateDisplayName(displayName);
        if (photoUrl != null) await user.updatePhotoURL(photoUrl);
        await user.reload();
      } catch (e) {
        throw 'Failed to update profile: $e';
      }
    } else {
      throw 'User not logged in';
    }
  }
}
