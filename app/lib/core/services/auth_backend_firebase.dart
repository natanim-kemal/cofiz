import 'package:firebase_auth/firebase_auth.dart';

class AuthBackendFirebase {
  AuthBackendFirebase({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;

  Future<UserCredential> signInWithCustomToken(String token) {
    return _auth.signInWithCustomToken(token);
  }

  Future<void> signOut() => _auth.signOut();

  Stream<User?> get authStateChanges => _auth.authStateChanges();
}
