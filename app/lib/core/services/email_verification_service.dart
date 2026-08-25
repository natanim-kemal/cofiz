import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Returns the signed-in user's email from Firebase Auth (authoritative),
/// falling back to [fallback] when auth has none.
String? currentAccountEmail({String? fallback}) {
  final authEmail = FirebaseAuth.instance.currentUser?.email;
  if (authEmail != null && authEmail.isNotEmpty) return authEmail;
  return (fallback == null || fallback.isEmpty) ? null : fallback;
}

class EmailVerificationService {
  FirebaseFunctions get _fns => FirebaseFunctions.instance;

  /// Requests a verification code. The server derives the destination from
  /// the caller's auth token, so [fallbackEmail] is informational only.
  /// Throws [EmailVerificationException] with a user-friendly message on
  /// failure (not-found = functions not deployed, resource-exhausted =
  /// resend cooldown, failed-precondition = account has no email).
  Future<void> requestCode(String? fallbackEmail) async {
    try {
      await _fns
          .httpsCallable('requestEmailVerification')
          .call({'email': fallbackEmail ?? ''});
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'resource-exhausted':
          throw EmailVerificationException(
              'Please wait a minute before requesting a new code.');
        case 'failed-precondition':
          throw EmailVerificationException(
              'Your account has no email address to verify.');
        case 'not-found':
        case 'unimplemented':
          throw EmailVerificationException(
              'Verification service unavailable. Is it deployed?');
        case 'unauthenticated':
          throw EmailVerificationException('Please sign in first.');
        default:
          throw EmailVerificationException(
              e.message ?? 'Could not send code. Try again.');
      }
    } catch (_) {
      throw EmailVerificationException(
          'Network error. Check your connection and try again.');
    }
  }

  /// Returns true when the code verified successfully. Throws
  /// [EmailVerificationException] with friendly messages otherwise.
  Future<bool> verifyCode(String code) async {
    try {
      final res =
          await _fns.httpsCallable('verifyEmailCode').call({'code': code});
      return (res.data as Map)['verified'] == true;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'deadline-exceeded':
          throw EmailVerificationException('Code expired. Resend a new one.',
              locked: true);
        case 'resource-exhausted':
          throw EmailVerificationException('Too many attempts. Resend code.',
              locked: true);
        case 'not-found':
          throw EmailVerificationException(
              'No code requested yet. Tap resend.');
        default:
          throw EmailVerificationException(
              e.message ?? 'Invalid or expired code.');
      }
    } catch (_) {
      throw EmailVerificationException(
          'Network error. Check your connection and try again.');
    }
  }
}

class EmailVerificationException implements Exception {
  final String message;
  final bool locked;
  EmailVerificationException(this.message, {this.locked = false});
  @override
  String toString() => message;
}

