import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  static const String _cachedAppUserKey = 'cached_app_user';

  Future<void> _initializeAuth() async {
    await _authService.enablePersistence();
    final currentUser = _authService.currentUser;

    if (currentUser != null) {
      final isValid = await _authService.isSessionValid();
      if (!isValid) {
        await _authService.signOut();
      } else {
        // Warm offline start: restore cached role instantly so AuthGate doesn't hang.
        final cached = await _loadCachedAppUser(currentUser.uid);
        if (cached != null) {
          _appUser = cached;
          _userRole = cached.role;
          _workerId = cached.workerId;
        }
      }
    }

    _authService.authStateChanges.listen((User? user) async {
      if (user != null) {
        _user = user;
        if (_status != AuthStatus.loading) {
          _status = AuthStatus.loading;
          notifyListeners();
        }
        await _fetchUserData(user.uid);
        unawaited(FCMService().saveTokenForUser(user.uid));
        _status = AuthStatus.authenticated;
        notifyListeners();
      } else {
        _user = null;
        _appUser = null;
        _userRole = null;
        _workerId = null;
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      }
    });
  }

  Future<void> _cacheAppUser(AppUser user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_cachedAppUserKey:${user.uid}',
          '${user.role.name}|${user.workerId ?? ''}|${user.displayName}|${user.email}');
    } catch (_) {}
  }

  Future<AppUser?> _loadCachedAppUser(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachedAppUserKey:$uid');
      if (raw == null) return null;
      final parts = raw.split('|');
      if (parts.length < 4) return null;
      final role = UserRole.values.firstWhere((r) => r.name == parts[0],
          orElse: () => UserRole.viewer);
      return AppUser(
        uid: uid,
        email: parts[3],
        displayName: parts[2],
        role: role,
        workerId: parts[1].isEmpty ? null : parts[1],
        createdAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchUserData(String uid) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 3));
      if (doc.exists) {
        _appUser = AppUser.fromFirestore(doc.data()!, uid);
        _userRole = _appUser!.role;
        _workerId = _appUser!.workerId;
        await _cacheAppUser(_appUser!);
        return;
      }
      debugPrint('[Auth] user doc not found (server): $uid');
    } catch (e) {
      debugPrint('[Auth] user doc fetch server failed: $e');
    }

    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.cache));
      if (doc.exists) {
        _appUser = AppUser.fromFirestore(doc.data()!, uid);
        _userRole = _appUser!.role;
        _workerId = _appUser!.workerId;
        await _cacheAppUser(_appUser!);
        return;
      }
      debugPrint('[Auth] user doc not found (cache): $uid');
    } catch (e) {
      debugPrint('[Auth] user doc fetch cache failed: $e');
    }

    final cached = await _loadCachedAppUser(uid);
    if (cached != null) {
      _appUser = cached;
      _userRole = cached.role;
      _workerId = cached.workerId;
      debugPrint('[Auth] user loaded from SharedPreferences: $uid role=${cached.role}');
    } else {
      debugPrint('[Auth] NO user data found for $uid — all sources failed');
    }
  }

  /// Sign in with email and password
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    try {
      _appUser = null;
      _userRole = null;
      _workerId = null;
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

  /// Locally reflect a successful email verification (server writes
  /// users/{uid}.emailVerified via Admin SDK; this updates the in-memory
  /// AppUser + cache so the UI flips without waiting for a stream).
  Future<void> markEmailVerified() async {
    final uid = _user?.uid;
    if (_appUser != null) {
      _appUser = AppUser(
        uid: _appUser!.uid,
        email: _appUser!.email,
        displayName: _appUser!.displayName,
        role: _appUser!.role,
        photoUrl: _appUser!.photoUrl,
        createdAt: _appUser!.createdAt,
        lastLoginAt: _appUser!.lastLoginAt,
        isActive: _appUser!.isActive,
        emailVerified: true,
        createdBy: _appUser!.createdBy,
        workerId: _appUser!.workerId,
      );
    }
    if (uid != null) {
      try {
        await _firestore.collection('users').doc(uid).update({
          'emailVerified': true,
        });
      } catch (_) {}
      // Refresh the cold-start cache with the verified state.
      if (_appUser != null) await _cacheAppUser(_appUser!);
    }
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
