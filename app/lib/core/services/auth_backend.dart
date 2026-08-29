import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

enum OtpProvider { telegram, whatsapp }

class AuthBackendException implements Exception {
  final int statusCode;
  final String errorCode;
  final String message;
  AuthBackendException(this.statusCode, this.errorCode, this.message);
  @override
  String toString() => 'AuthBackendException($statusCode/$errorCode): $message';
}

class RequestOtpResult {
  final String verificationId;
  final int expiresInSeconds;
  RequestOtpResult({required this.verificationId, required this.expiresInSeconds});
}

class VerifyOtpResult {
  final String customToken;
  final String uid;
  final bool isNewUser;
  VerifyOtpResult({required this.customToken, required this.uid, required this.isNewUser});
}

class AuthBackend {
  AuthBackend({
    required this.baseUrl,
    this.secret,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String baseUrl;
  final String? secret;
  final http.Client _client;

  Map<String, String> _headers({bool json = true}) {
    return {
      if (json) 'content-type': 'application/json',
      if (secret != null && secret!.isNotEmpty) 'x-relay-secret': secret!,
    };
  }

  Future<RequestOtpResult> requestOtp({
    required String phone,
    required OtpProvider provider,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/auth/whatsapp/start'),
      headers: _headers(),
      body: jsonEncode({
        'phone': phone,
        'provider': provider.name,
      }),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw AuthBackendException(res.statusCode, body['error']?.toString() ?? 'unknown', body['message']?.toString() ?? '');
    }
    return RequestOtpResult(
      verificationId: body['verificationId'] as String,
      expiresInSeconds: (body['expiresInSeconds'] as num).toInt(),
    );
  }

  Future<VerifyOtpResult> verifyOtp({
    required String phone,
    required OtpProvider provider,
    required String verificationId,
    required String code,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/auth/whatsapp/verify'),
      headers: _headers(),
      body: jsonEncode({
        'phone': phone,
        'provider': provider.name,
        'verificationId': verificationId,
        'code': code,
      }),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw AuthBackendException(res.statusCode, body['error']?.toString() ?? 'unknown', body['message']?.toString() ?? '');
    }
    return VerifyOtpResult(
      customToken: body['customToken'] as String,
      uid: body['uid'] as String,
      isNewUser: body['isNewUser'] as bool,
    );
  }

  Future<VerifyOtpResult> authTelegram(Map<String, String> fields) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/auth/telegram'),
      headers: _headers(),
      body: jsonEncode(fields),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw AuthBackendException(
        res.statusCode,
        body['error']?.toString() ?? 'unknown',
        body['message']?.toString() ?? '',
      );
    }
    return VerifyOtpResult(
      customToken: body['customToken'] as String,
      uid: body['uid'] as String,
      isNewUser: body['isNewUser'] as bool,
    );
  }
}
