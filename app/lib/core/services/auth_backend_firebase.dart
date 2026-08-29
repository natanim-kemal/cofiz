import 'package:firebase_auth/firebase_auth.dart';

class AuthBackendFirebase {
  AuthBackendFirebase({FirebaseAuth? auth}) : _auth = auth;
  final FirebaseAuth? _auth;
  FirebaseAuth get _resolved => _auth ?? FirebaseAuth.instance;

  Future<UserCredential> signInWithCustomToken(String token) {
    return _resolved.signInWithCustomToken(token);
  }

  Future<void> signOut() => _resolved.signOut();

  Stream<User?> get authStateChanges => _resolved.authStateChanges();
}
