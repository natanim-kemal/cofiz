import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/offline_cache_service.dart';
import '../models/user_model.dart';

enum AuthStatus {
  uninitialized,
  authenticated,
  unauthenticated,
  loading,
}

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  AuthStatus _status = AuthStatus.uninitialized;
  String? _errorMessage;
  User? _user;
  AppUser? _appUser; // User data from Firestore
  UserRole? _userRole;
  String? _workerId; // If user is a worker

  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;
  User? get user => _user;
  AppUser? get appUser => _appUser;
  UserRole? get userRole => _userRole;
  String? get workerId => _workerId;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isWorker => _userRole == UserRole.worker && _workerId != null;
  bool get isAdmin => _userRole == UserRole.admin;
  bool get isViewer => _userRole == UserRole.viewer;

  AuthProvider() {
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    await _authService.enablePersistence();
    final currentUser = _authService.currentUser;

    if (currentUser != null) {
      final isValid = await _authService.isSessionValid();
      if (!isValid) {
        await _authService.signOut();
      }
    }

    _authService.authStateChanges.listen((User? user) async {
      if (user != null) {
        _user = user;
        await _fetchUserData(user.uid);
        _status = AuthStatus.authenticated;
      } else {
        _user = null;
        _appUser = null;
        _userRole = null;
        _workerId = null;
        _status = AuthStatus.unauthenticated;
      }
      notifyListeners();
    });
  }

  /// Fetch user data from Firestore
  Future<void> _fetchUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();

      if (doc.exists) {
        _appUser = AppUser.fromFirestore(doc.data()!, uid);
        _userRole = _appUser!.role;
        _workerId = _appUser!.workerId;
      } else {
        // User document doesn't exist - must be manually created by admin
        debugPrint('ERROR: User document not found for uid: $uid');
        debugPrint('This user must be manually created in Firestore');
        _userRole = null;
        _appUser = null;
        _workerId = null;
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      _userRole = null;
      _appUser = null;
    }
  }

  /// Sign in with email and password
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    try {
      _status = AuthStatus.loading;
      _errorMessage = null;
      notifyListeners();

      final credential = await _authService.signInWithEmailPassword(
        email: email,
        password: password,
      );

      if (credential != null && credential.user != null) {
        _user = credential.user;

        // Fetch user role and data from Firestore
        await _fetchUserData(credential.user!.uid);

        // Save FCM token for push notifications
        await FCMService().saveTokenForUser(credential.user!.uid);

        _status = AuthStatus.authenticated;
        _errorMessage = null;
        notifyListeners();
        return true;
      } else {
        _status = AuthStatus.unauthenticated;
        _errorMessage = 'Login failed. Please try again.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _errorMessage =
          e is String ? e : 'Login failed. Please check your connection.';
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      print('DEBUG: Starting sign out...');
      _status = AuthStatus.loading;
      notifyListeners();

      // Remove FCM token before signing out
      if (_user != null) {
        await FCMService().removeTokenForUser(_user!.uid);
      }

      await _authService.signOut();

      await OfflineCacheService().clearAllCache(keepOutbox: true);

      // Explicitly clear all user data
      _user = null;
      _appUser = null;
      _userRole = null;
      _workerId = null;
      _appUser = null;
      _userRole = null;
      _workerId = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = null;

      notifyListeners();
    } catch (e) {
      print('DEBUG: Sign out ERROR: $e');
      // Even on error, try to clear state
      _user = null;
      _appUser = null;
      _userRole = null;
      _workerId = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = e.toString();
      // Even if firebase signout fails, we should clear local state
      _user = null;
      _appUser = null;
      _userRole = null;
      _workerId = null;
      _status = AuthStatus.unauthenticated;
      try {
        await OfflineCacheService().clearAllCache(keepOutbox: true);
      } catch (_) {}
      notifyListeners();
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Get user email
  String? getUserEmail() {
    return _authService.getUserEmail();
  }

  /// Get user display name
  String? getUserDisplayName() {
    return _authService.getUserDisplayName();
  }

  /// Get user ID
  String? getUserId() {
    return _authService.getUserId();
  }

  /// Check session validity
  Future<bool> isSessionValid() async {
    return await _authService.isSessionValid();
  }

  /// Reset password
  Future<bool> resetPassword({required String email}) async {
    try {
      await _authService.resetPassword(email: email);
      return true;
    } catch (e) {
      _errorMessage =
          e is String ? e : 'Failed to send reset link. Please try again.';
      notifyListeners();
      return false;
    }
  }

  /// Update user profile
  Future<bool> updateUserProfile(
      {String? displayName, String? photoUrl}) async {
    try {
      _status = AuthStatus.loading;
      notifyListeners();

      await _authService.updateProfile(
          displayName: displayName, photoUrl: photoUrl);

      // Refresh user data
      _user = _authService.currentUser;

      // Persist to Firestore so appUser reflects the change app-wide
      final uid = _user?.uid;
      if (uid != null) {
        final updates = <String, dynamic>{};
        if (displayName != null) updates['displayName'] = displayName;
        if (photoUrl != null) updates['photoUrl'] = photoUrl;
        if (updates.isNotEmpty) {
          await _firestore.collection('users').doc(uid).update(updates);
        }
        if (_appUser != null) {
          _appUser =
              _appUser!.copyWith(displayName: displayName, photoUrl: photoUrl);
        }
      }

      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e is String ? e : 'Update failed. Please try again.';
      _status = AuthStatus.authenticated;
      notifyListeners();
      return false;
    }
  }
}
