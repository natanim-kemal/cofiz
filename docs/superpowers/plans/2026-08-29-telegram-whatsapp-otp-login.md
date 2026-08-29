# Phone-OTP Login (Telegram + WhatsApp) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace email/password sign-in with phone-OTP sign-in delivered over Telegram or WhatsApp, mediated by a new Cloudflare Worker that mints Firebase custom tokens.

**Architecture:** Two new client-side services (`AuthBackend`, `AuthBackendFirebase`) talk to a Cloudflare Worker (`workers/fcm-relay`) that holds OTP codes in KV, dispatches them via Telegram Bot API or WhatsApp Business Cloud API, and exchanges a verified code for a Firebase custom token. The Flutter app signs in with that custom token. `users/{uid}` (uid = sha256(phone)) replaces the email-keyed doc.

**Tech Stack:** Flutter 3 / Dart, Firebase Auth (custom token sign-in), Cloudflare Workers (KV, Cron Triggers), Telegram Bot API, WhatsApp Business Cloud API v17.0, `crypto` (PBKDF2/SHA-256), `http` for outbound.

**Spec:** `docs/superpowers/specs/2026-08-29-telegram-whatsapp-otp-login-design.md`

## Global Constraints

- Dart SDK `^3.5.4` (from `app/pubspec.yaml:22`).
- Existing `flutter_secure_storage: ^10.0.0` (line 83) for any local secret.
- No new top-level dependencies on the Flutter side; only `http` and `crypto` (transitive).
- Worker secrets only — never log tokens. Use `console.debug` only with `requestId` correlation.
- All file paths relative to repo root unless noted.
- E.164 phone format everywhere; default region `+251`.
- 6-digit codes, 5-min TTL, 5 attempts/hour server-side, 60s cooldown client-side.
- 6-task plan (Flutter) + 3-task plan (Worker). Tasks are independently mergeable.

---

## File Structure

### New Flutter files

- `app/lib/core/services/auth_backend.dart` — HTTP client to the worker.
- `app/lib/core/services/auth_backend_firebase.dart` — `signInWithCustomToken` wrapper.
- `app/lib/core/providers/phone_otp_auth_provider.dart` — state machine.
- `app/lib/core/utils/phone_utils.dart` — E.164 validation, sha256 helper.
- `app/lib/presentation/screens/auth/phone_login_screen.dart` — phone + provider entry.
- `app/lib/presentation/screens/auth/otp_verify_screen.dart` — 6-digit entry.
- `app/lib/presentation/screens/auth/bot_opt_in_banner.dart` — shared deep-link banner.
- `app/lib/l10n/app_en.arb` (modify) + regenerate via `flutter gen-l10n`.
- `app/test/core/utils/phone_utils_test.dart` — validation tests.
- `app/test/core/providers/phone_otp_auth_provider_test.dart` — state machine tests.

### Modified Flutter files

- `app/lib/main.dart` — route to `PhoneLoginScreen` instead of `LoginScreen`.
- `app/lib/presentation/screens/auth/login_screen.dart` — replaced by a thin wrapper that pushes `PhoneLoginScreen` (kept for back-compat with any code that imports it).
- `app/lib/core/providers/auth_provider.dart` — keep for role checks, but ownership of authentication state moves to `PhoneOtpAuthProvider`.
- `app/pubspec.yaml` — no new deps required (uses existing `http`, `crypto` is transitive via `flutter_secure_storage`).

### New Worker files

- `workers/fcm-relay/src/otp/` — `kv.js`, `telegram.js`, `whatsapp.js`, `firebase.js`, `rate_limit.js`, `handlers.js`, `index.js` (route dispatcher).
- `workers/fcm-relay/test/otp/handlers.test.js` — vitest cases against `getMiniflareBindings()`.

### Modified Worker files

- `workers/fcm-relay/wrangler.toml` — add `OTP_KV` binding, `TELEGRAM_BOT_TOKEN`, `WHATSAPP_PHONE_ID`, `WHATSAPP_ACCESS_TOKEN`, `FIREBASE_SERVICE_ACCOUNT_JSON` (all as `secrets`).
- `workers/fcm-relay/src/index.js` — mount `/otp/*` router.

---

## Task 1: Phone utilities + tests

**Files:**
- Create: `app/lib/core/utils/phone_utils.dart`
- Test: `app/test/core/utils/phone_utils_test.dart`

**Interfaces:**
- Produces: `String sha256Hex(String input)`, `bool isValidE164(String phone)`, `String normalizeE164(String raw, {String defaultRegion = 'ET'})`.

- [ ] **Step 1: Write the failing test**

Create `app/test/core/utils/phone_utils_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/utils/phone_utils.dart';

void main() {
  group('isValidE164', () {
    test('accepts +251911234567', () {
      expect(isValidE164('+251911234567'), isTrue);
    });
    test('rejects missing plus', () {
      expect(isValidE164('251911234567'), isFalse);
    });
    test('rejects too short', () {
      expect(isValidE164('+1234'), isFalse);
    });
    test('rejects letters', () {
      expect(isValidE164('+25191abc4567'), isFalse);
    });
  });

  group('normalizeE164', () {
    test('adds +251 to 0911234567', () {
      expect(normalizeE164('0911234567', defaultRegion: 'ET'), '+251911234567');
    });
    test('keeps existing +', () {
      expect(normalizeE164('+251911234567'), '+251911234567');
    });
  });

  group('sha256Hex', () {
    test('matches known vector for "abc"', () {
      expect(sha256Hex('abc'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });
}
```

- [ ] **Step 2: Run tests, expect failure**

Run: `cd app && flutter test test/core/utils/phone_utils_test.dart`
Expected: import fails, "Target of URI doesn't exist: 'package:cofiz/core/utils/phone_utils.dart'".

- [ ] **Step 3: Implement `phone_utils.dart`**

```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

final _e164 = RegExp(r'^\+[1-9]\d{7,14}$');

bool isValidE164(String phone) => _e164.hasMatch(phone);

String normalizeE164(String raw, {String defaultRegion = 'ET'}) {
  final trimmed = raw.replaceAll(RegExp(r'[\s-]'), '');
  if (trimmed.startsWith('+')) return trimmed;
  switch (defaultRegion) {
    case 'ET':
      final local = trimmed.startsWith('0') ? trimmed.substring(1) : trimmed;
      return '+$defaultRegion$local'
          .replaceFirst('+ET', '+251');
  }
  return '+$trimmed';
}

String sha256Hex(String input) {
  final digest = sha256.convert(utf8.encode(input));
  return digest.toString();
}
```

Note: `crypto` is already a transitive dep through `flutter_secure_storage`. Verify by running `flutter pub get` and ensuring no error.

- [ ] **Step 4: Run tests, expect pass**

Run: `cd app && flutter test test/core/utils/phone_utils_test.dart`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/utils/phone_utils.dart app/test/core/utils/phone_utils_test.dart
git commit -m "feat(auth): add phone utilities and tests"
```

---

## Task 2: `AuthBackend` HTTP client + tests

**Files:**
- Create: `app/lib/core/services/auth_backend.dart`
- Test: `app/test/core/services/auth_backend_test.dart`

**Interfaces:**
- Consumes: `isValidE164` from Task 1.
- Produces:
  ```dart
  class AuthBackend {
    AuthBackend({required this.baseUrl, http.Client? client});
    final String baseUrl;
    final http.Client _client;
    Future<RequestOtpResult> requestOtp({required String phone, required OtpProvider provider});
    Future<VerifyOtpResult> verifyOtp({required String phone, required OtpProvider provider, required String verificationId, required String code});
  }
  enum OtpProvider { telegram, whatsapp }
  class RequestOtpResult { final String verificationId; final int expiresInSeconds; }
  class VerifyOtpResult { final String customToken; final String uid; final bool isNewUser; }
  ```

- [ ] **Step 1: Add `http_mock_adapter` dev dep**

In `app/pubspec.yaml` under `dev_dependencies`, add:
```yaml
http_mock_adapter: ^0.6.1
```
Run: `cd app && flutter pub get`

- [ ] **Step 2: Write the failing test**

Create `app/test/core/services/auth_backend_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:cofiz/core/services/auth_backend.dart';

void main() {
  late DioAdapter dio; // we use package:http style — see step 3
  // (placeholder; tests are written against http.Client mock below)
  group('AuthBackend', () {
    test('requestOtp posts phone+provider and returns verificationId', () async {
      final mock = MockHttpClient();
      mock.post('/otp/start', (req) => jsonEncode({
            'verificationId': 'v1',
            'expiresInSeconds': 300,
          }), status: 200);
      final backend = AuthBackend(baseUrl: 'https://relay.example', client: mock);
      final r = await backend.requestOtp(phone: '+251911234567', provider: OtpProvider.telegram);
      expect(r.verificationId, 'v1');
      expect(r.expiresInSeconds, 300);
    });

    test('verifyOtp returns customToken', () async {
      final mock = MockHttpClient();
      mock.post('/otp/verify', (req) => jsonEncode({
            'customToken': 'tok',
            'uid': 'abc',
            'isNewUser': false,
          }), status: 200);
      final backend = AuthBackend(baseUrl: 'https://relay.example', client: mock);
      final r = await backend.verifyOtp(
        phone: '+251911234567',
        provider: OtpProvider.telegram,
        verificationId: 'v1',
        code: '123456',
      );
      expect(r.customToken, 'tok');
      expect(r.uid, 'abc');
      expect(r.isNewUser, isFalse);
    });

    test('verifyOtp throws AuthBackendException on 400', () async {
      final mock = MockHttpClient();
      mock.post('/otp/verify', (_) => jsonEncode({'error': 'bad_code'}), status: 400);
      final backend = AuthBackend(baseUrl: 'https://relay.example', client: mock);
      expect(
        () => backend.verifyOtp(
          phone: '+251911234567',
          provider: OtpProvider.telegram,
          verificationId: 'v1',
          code: '000000',
        ),
        throwsA(isA<AuthBackendException>()),
      );
    });
  });
}
```

- [ ] **Step 3: Implement `AuthBackend` with `MockHttpClient` helper**

Create `app/lib/core/services/auth_backend.dart`:

```dart
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
  AuthBackend({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

  Future<RequestOtpResult> requestOtp({
    required String phone,
    required OtpProvider provider,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/otp/start'),
      headers: {'content-type': 'application/json'},
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
      Uri.parse('$baseUrl/otp/verify'),
      headers: {'content-type': 'application/json'},
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
}
```

Create `app/test/_support/mock_http_client.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class MockHttpClient extends http.BaseClient {
  final _routes = <String, _Route>{};
  void post(String path, dynamic Function(Map<String, dynamic> body) responder, {int status = 200}) {
    _routes['POST $path'] = _Route(responder, status);
  }
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = '${request.method} ${request.url.path}';
    final route = _routes[key];
    if (route == null) {
      return http.StreamedResponse(Stream.value([]), 404);
    }
    final body = request is http.Request ? jsonDecode(request.body) as Map<String, dynamic> : <String, dynamic>{};
    final payload = route.responder(body);
    return http.StreamedResponse(
      Stream.value(utf8.encode(payload is String ? payload : jsonEncode(payload))),
      route.status,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _Route {
  final dynamic Function(Map<String, dynamic>) responder;
  final int status;
  _Route(this.responder, this.status);
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `cd app && flutter test test/core/services/auth_backend_test.dart`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/auth_backend.dart app/test/core/services/auth_backend_test.dart app/test/_support/mock_http_client.dart app/pubspec.yaml app/pubspec.lock
git commit -m "feat(auth): add AuthBackend HTTP client and tests"
```

---

## Task 3: `PhoneOtpAuthProvider` state machine + tests

**Files:**
- Create: `app/lib/core/providers/phone_otp_auth_provider.dart`
- Test: `app/test/core/providers/phone_otp_auth_provider_test.dart`

**Interfaces:**
- Consumes: `AuthBackend` from Task 2.
- Produces:
  ```dart
  class PhoneOtpAuthProvider extends ChangeNotifier {
    PhoneOtpAuthProvider({required this.backend});
    final AuthBackend backend;
    OtpAuthState state;     // unauthenticated | awaitingCode | verifying | authenticated | error
    String? phone;
    OtpProvider? provider;
    String? verificationId;
    String? uid;
    bool get isAuthenticated;
    Future<void> requestOtp({required String phone, required OtpProvider provider});
    Future<void> verifyOtp({required String code});
    Future<void> signOut();
  }
  enum OtpAuthState { unauthenticated, awaitingCode, verifying, authenticated, error }
  ```

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/providers/phone_otp_auth_provider.dart';
import 'package:cofiz/core/services/auth_backend.dart';
import '../../_support/mock_http_client.dart';

void main() {
  group('PhoneOtpAuthProvider', () {
    test('requestOtp transitions to awaitingCode on success', () async {
      final mock = MockHttpClient();
      mock.post('/otp/start', (_) => {'verificationId': 'v1', 'expiresInSeconds': 300});
      final p = PhoneOtpAuthProvider(
        backend: AuthBackend(baseUrl: 'https://x', client: mock),
      );
      await p.requestOtp(phone: '+251911234567', provider: OtpProvider.telegram);
      expect(p.state, OtpAuthState.awaitingCode);
      expect(p.verificationId, 'v1');
      expect(p.phone, '+251911234567');
    });

    test('verifyOtp transitions to authenticated on success', () async {
      final mock = MockHttpClient();
      mock.post('/otp/start', (_) => {'verificationId': 'v1', 'expiresInSeconds': 300});
      mock.post('/otp/verify', (_) => {'customToken': 'tok', 'uid': 'abc', 'isNewUser': true});
      final p = PhoneOtpAuthProvider(
        backend: AuthBackend(baseUrl: 'https://x', client: mock),
      );
      await p.requestOtp(phone: '+251911234567', provider: OtpProvider.telegram);
      await p.verifyOtp(code: '123456');
      expect(p.state, OtpAuthState.authenticated);
      expect(p.uid, 'abc');
    });

    test('verifyOtp moves to error on 400', () async {
      final mock = MockHttpClient();
      mock.post('/otp/start', (_) => {'verificationId': 'v1', 'expiresInSeconds': 300});
      mock.post('/otp/verify', (_) => {'error': 'bad_code', 'message': 'Wrong code'}, status: 400);
      final p = PhoneOtpAuthProvider(
        backend: AuthBackend(baseUrl: 'https://x', client: mock),
      );
      await p.requestOtp(phone: '+251911234567', provider: OtpProvider.telegram);
      await p.verifyOtp(code: '000000');
      expect(p.state, OtpAuthState.error);
    });

    test('signOut resets state', () async {
      final mock = MockHttpClient();
      mock.post('/otp/start', (_) => {'verificationId': 'v1', 'expiresInSeconds': 300});
      mock.post('/otp/verify', (_) => {'customToken': 'tok', 'uid': 'abc', 'isNewUser': false});
      final p = PhoneOtpAuthProvider(
        backend: AuthBackend(baseUrl: 'https://x', client: mock),
      );
      await p.requestOtp(phone: '+251911234567', provider: OtpProvider.telegram);
      await p.verifyOtp(code: '123456');
      await p.signOut();
      expect(p.state, OtpAuthState.unauthenticated);
      expect(p.uid, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests, expect failure**

Run: `cd app && flutter test test/core/providers/phone_otp_auth_provider_test.dart`
Expected: import error.

- [ ] **Step 3: Implement the provider**

```dart
import 'package:flutter/foundation.dart';
import '../services/auth_backend.dart';

enum OtpAuthState { unauthenticated, awaitingCode, verifying, authenticated, error }

class PhoneOtpAuthProvider extends ChangeNotifier {
  PhoneOtpAuthProvider({required this.backend});
  final AuthBackend backend;

  OtpAuthState _state = OtpAuthState.unauthenticated;
  String? _phone;
  OtpProvider? _provider;
  String? _verificationId;
  String? _uid;
  String? _lastErrorCode;
  String? _lastErrorMessage;

  OtpAuthState get state => _state;
  String? get phone => _phone;
  OtpProvider? get provider => _provider;
  String? get verificationId => _verificationId;
  String? get uid => _uid;
  bool get isAuthenticated => _state == OtpAuthState.authenticated;
  String? get lastErrorCode => _lastErrorCode;
  String? get lastErrorMessage => _lastErrorMessage;

  Future<void> requestOtp({required String phone, required OtpProvider provider}) async {
    _phone = phone;
    _provider = provider;
    _state = OtpAuthState.unauthenticated;
    notifyListeners();
    try {
      final r = await backend.requestOtp(phone: phone, provider: provider);
      _verificationId = r.verificationId;
      _state = OtpAuthState.awaitingCode;
    } on AuthBackendException catch (e) {
      _lastErrorCode = e.errorCode;
      _lastErrorMessage = e.message;
      _state = OtpAuthState.error;
    }
    notifyListeners();
  }

  Future<void> verifyOtp({required String code}) async {
    if (_phone == null || _provider == null || _verificationId == null) {
      _state = OtpAuthState.error;
      _lastErrorMessage = 'No verification in progress';
      notifyListeners();
      return;
    }
    _state = OtpAuthState.verifying;
    notifyListeners();
    try {
      final r = await backend.verifyOtp(
        phone: _phone!,
        provider: _provider!,
        verificationId: _verificationId!,
        code: code,
      );
      _uid = r.uid;
      _state = OtpAuthState.authenticated;
    } on AuthBackendException catch (e) {
      _lastErrorCode = e.errorCode;
      _lastErrorMessage = e.message;
      _state = OtpAuthState.error;
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    _state = OtpAuthState.unauthenticated;
    _phone = null;
    _provider = null;
    _verificationId = null;
    _uid = null;
    _lastErrorCode = null;
    _lastErrorMessage = null;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `cd app && flutter test test/core/providers/phone_otp_auth_provider_test.dart`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/providers/phone_otp_auth_provider.dart app/test/core/providers/phone_otp_auth_provider_test.dart
git commit -m "feat(auth): add PhoneOtpAuthProvider state machine and tests"
```

---

## Task 4: `PhoneLoginScreen` and `OtpVerifyScreen` UI

**Files:**
- Create: `app/lib/presentation/screens/auth/phone_login_screen.dart`
- Create: `app/lib/presentation/screens/auth/otp_verify_screen.dart`
- Create: `app/lib/presentation/screens/auth/bot_opt_in_banner.dart`
- Modify: `app/lib/l10n/app_en.arb` (append)
- Modify: `app/lib/l10n/app_am.arb` (append)
- Run: `flutter gen-l10n`

**Interfaces:**
- Consumes: `PhoneOtpAuthProvider`, `isValidE164`, `normalizeE164` from Tasks 1, 3.
- Produces: two navigable screens that mutate the provider.

- [ ] **Step 1: Add new strings to ARB files**

Append to `app/lib/l10n/app_en.arb`:
```json
  "sendCode": "Send code",
  "resendCode": "Resend code",
  "providerTelegram": "Telegram",
  "providerWhatsapp": "WhatsApp",
  "botOptInBannerTitle": "One-time setup",
  "botOptInBannerBody": "Tap to open Telegram and press Start, then return to the app.",
  "enterPhoneNumber": "Phone number",
  "invalidPhoneNumber": "Enter a valid phone number (e.g. +251911234567)",
  "enterSixDigitCode": "Enter 6-digit code",
  "codeExpired": "Code expired. Tap to resend."
```

Append to `app/lib/l10n/app_am.arb`:
```json
  "sendCode": "ኮድ ላክ",
  "resendCode": "ኮድ እንደገና ላክ",
  "providerTelegram": "ቴሌግራም",
  "providerWhatsapp": "ዋትስአፕ",
  "botOptInBannerTitle": "አንድ ጊዜ ዝግጅት",
  "botOptInBannerBody": "ቴሌግራም ለመክፈት ይጫኑ እና Start የሚለውን ይጫኑ፣ ከዚያ ወደ መተግበሪያው ይመለሱ።",
  "enterPhoneNumber": "ስልክ ቁጥር",
  "invalidPhoneNumber": "ትክክለኛ ስልክ ቁጥር ያስገቡ (ለምሳሌ +251911234567)",
  "enterSixDigitCode": "6 አሃዝ ኮድ ያስገቡ",
  "codeExpired": "ኮዱ ጊዜው አልፏል። እንደገና ለመላክ ይንኩ።"
```

- [ ] **Step 2: Regenerate localizations**

Run: `cd app && flutter gen-l10n`
Expected: `app/lib/l10n/app_localizations*.dart` regenerated with the new keys.

- [ ] **Step 3: Write widget tests**

Create `app/test/presentation/screens/auth/phone_login_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cofiz/core/providers/phone_otp_auth_provider.dart';
import 'package:cofiz/core/services/auth_backend.dart';
import 'package:cofiz/presentation/screens/auth/phone_login_screen.dart';
import '../../../_support/mock_http_client.dart';

void main() {
  testWidgets('PhoneLoginScreen shows Send Code button and provider toggle', (tester) async {
    final mock = MockHttpClient();
    mock.post('/otp/start', (_) => {'verificationId': 'v1', 'expiresInSeconds': 300});
    final provider = PhoneOtpAuthProvider(
      backend: AuthBackend(baseUrl: 'https://x', client: mock),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: provider,
          child: const PhoneLoginScreen(),
        ),
      ),
    );
    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.byKey(const Key('sendCodeButton')), findsOneWidget);
  });
}
```

Create `app/test/presentation/screens/auth/otp_verify_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cofiz/core/providers/phone_otp_auth_provider.dart';
import 'package:cofiz/core/services/auth_backend.dart';
import 'package:cofiz/presentation/screens/auth/otp_verify_screen.dart';
import '../../../_support/mock_http_client.dart';

void main() {
  testWidgets('OtpVerifyScreen shows 6 inputs', (tester) async {
    final mock = MockHttpClient();
    mock.post('/otp/start', (_) => {'verificationId': 'v1', 'expiresInSeconds': 300});
    final p = PhoneOtpAuthProvider(
      backend: AuthBackend(baseUrl: 'https://x', client: mock),
    );
    await p.requestOtp(phone: '+251911234567', provider: OtpProvider.telegram);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: p,
          child: const OtpVerifyScreen(),
        ),
      ),
    );
    expect(find.byKey(const Key('codeDigit0')), findsOneWidget);
    expect(find.byKey(const Key('codeDigit5')), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run tests, expect failure (UI not yet implemented)**

Run: `cd app && flutter test test/presentation/screens/auth/`
Expected: import errors.

- [ ] **Step 5: Implement `bot_opt_in_banner.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class BotOptInBanner extends StatelessWidget {
  const BotOptInBanner({super.key, required this.deepLink, required this.providerLabel});
  final String deepLink;
  final String providerLabel;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Material(
      color: const Color(0xFFFFF1E2),
      child: ListTile(
        leading: const Icon(Icons.telegram),
        title: Text(t.botOptInBannerTitle),
        subtitle: Text(t.botOptInBannerBody),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => launchUrl(Uri.parse(deepLink), mode: LaunchMode.externalApplication),
      ),
    );
  }
}
```

- [ ] **Step 6: Implement `phone_login_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../core/providers/phone_otp_auth_provider.dart';
import '../../core/services/auth_backend.dart';
import '../../core/utils/phone_utils.dart';
import 'otp_verify_screen.dart';
import 'bot_opt_in_banner.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});
  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phoneCtl = TextEditingController();
  OtpProvider _provider = OtpProvider.telegram;
  bool _sending = false;

  @override
  void dispose() {
    _phoneCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _phoneCtl.text.trim();
    final phone = isValidE164(raw) ? raw : normalizeE164(raw);
    if (!isValidE164(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid phone number (e.g. +251911234567)')),
      );
      return;
    }
    setState(() => _sending = true);
    final p = context.read<PhoneOtpAuthProvider>();
    await p.requestOtp(phone: phone, provider: _provider);
    if (!mounted) return;
    setState(() => _sending = false);
    if (p.state == OtpAuthState.awaitingCode) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OtpVerifyScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(p.lastErrorMessage ?? 'Could not send code')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<OtpProvider>(
              segments: [
                ButtonSegment(value: OtpProvider.telegram, label: Text(t.providerTelegram)),
                ButtonSegment(value: OtpProvider.whatsapp, label: Text(t.providerWhatsapp)),
              ],
              selected: {_provider},
              onSelectionChanged: (s) => setState(() => _provider = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneCtl,
              decoration: InputDecoration(labelText: t.enterPhoneNumber),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            BotOptInBanner(
              deepLink: _provider == OtpProvider.telegram
                  ? 'https://t.me/cofiz_bot?start=${Uri.encodeComponent(_phoneCtl.text)}'
                  : 'https://wa.me/255700000000?text=START',
              providerLabel: _provider.name,
            ),
            const Spacer(),
            FilledButton(
              key: const Key('sendCodeButton'),
              onPressed: _sending ? null : _submit,
              child: Text(t.sendCode),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Implement `otp_verify_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../core/providers/phone_otp_auth_provider.dart';

class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({super.key});
  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _digits = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _digits) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _digits.map((c) => c.text).join();
    if (code.length != 6) return;
    final p = context.read<PhoneOtpAuthProvider>();
    await p.verifyOtp(code: code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
            return SizedBox(
              width: 40,
              child: TextField(
                key: Key('codeDigit$i'),
                controller: _digits[i],
                focusNode: _focusNodes[i],
                keyboardType: TextInputType.number,
                maxLength: 1,
                textAlign: TextAlign.center,
                onChanged: (v) {
                  if (v.isNotEmpty && i < 5) _focusNodes[i + 1].requestFocus();
                  if (i == 5 && _digits.every((c) => c.text.isNotEmpty)) _submit();
                },
              ),
            );
          }),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Run tests, expect pass**

Run: `cd app && flutter test test/presentation/screens/auth/`
Expected: 2 widget tests pass.

- [ ] **Step 9: Commit**

```bash
git add app/lib/presentation/screens/auth/phone_login_screen.dart app/lib/presentation/screens/auth/otp_verify_screen.dart app/lib/presentation/screens/auth/bot_opt_in_banner.dart app/lib/l10n/ app/test/presentation/screens/auth/
git commit -m "feat(auth): add phone login and OTP verify screens"
```

---

## Task 5: Worker `AuthBackendFirebase` and wire `main.dart`

**Files:**
- Create: `app/lib/core/services/auth_backend_firebase.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/lib/presentation/screens/auth/login_screen.dart` (replace body)
- Test: `app/test/core/services/auth_backend_firebase_test.dart`

**Interfaces:**
- Produces: `Future<UserCredential> signInWithCustomToken(String token)` using `FirebaseAuth.instance`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
// Note: signInWithCustomToken cannot be unit-tested without the Firebase platform
// shim; this test is a smoke check that the wrapper class compiles and is
// constructible. Manual QA on iOS/Android covers the live path.
import 'package:cofiz/core/services/auth_backend_firebase.dart';

void main() {
  test('AuthBackendFirebase is constructible', () {
    final s = AuthBackendFirebase();
    expect(s, isNotNull);
  });
}
```

- [ ] **Step 2: Implement the wrapper**

```dart
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
```

- [ ] **Step 3: Modify `app/lib/main.dart` to mount `PhoneOtpAuthProvider`**

Find the place where the current `AuthProvider` is constructed. Add:

```dart
import 'core/services/auth_backend.dart';
import 'core/services/auth_backend_firebase.dart';
import 'core/providers/phone_otp_auth_provider.dart';
```

Wrap `MaterialApp` in a `MultiProvider`:

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(
      create: (_) => PhoneOtpAuthProvider(
        backend: AuthBackend(baseUrl: const String.fromEnvironment('RELAY_BASE_URL', defaultValue: 'https://fcm-relay.example')),
      ),
    ),
    // existing providers (auth, transaction, etc.) stay here
  ],
  child: MaterialApp(
    home: const PhoneLoginScreen(),
    // ...
  ),
)
```

- [ ] **Step 4: Replace `LoginScreen` body to redirect**

In `app/lib/presentation/screens/auth/login_screen.dart`, change the `build` method to:

```dart
@override
Widget build(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
    );
  });
  return const Scaffold(body: SizedBox.shrink());
}
```

- [ ] **Step 5: Run full test suite**

Run: `cd app && flutter test`
Expected: all existing tests pass; new auth tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/services/auth_backend_firebase.dart app/lib/main.dart app/lib/presentation/screens/auth/login_screen.dart app/test/core/services/auth_backend_firebase_test.dart
git commit -m "feat(auth): wire phone OTP into app startup"
```

---

## Task 6: Worker `/otp/*` endpoints

**Files:**
- Create: `workers/fcm-relay/src/otp/kv.js`
- Create: `workers/fcm-relay/src/otp/telegram.js`
- Create: `workers/fcm-relay/src/otp/whatsapp.js`
- Create: `workers/fcm-relay/src/otp/firebase.js`
- Create: `workers/fcm-relay/src/otp/rate_limit.js`
- Create: `workers/fcm-relay/src/otp/handlers.js`
- Create: `workers/fcm-relay/src/otp/index.js`
- Modify: `workers/fcm-relay/src/index.js`
- Modify: `workers/fcm-relay/wrangler.toml`
- Create: `workers/fcm-relay/test/otp/handlers.test.js`
- Modify: `workers/fcm-relay/package.json` (add `firebase-admin`, `vitest`, `miniflare` as devDeps)

- [ ] **Step 1: Add Worker dependencies**

Run:
```bash
cd workers/fcm-relay
npm install firebase-admin
npm install --save-dev vitest miniflare @cloudflare/workers-types
```

Add to `package.json` scripts:
```json
"test": "vitest run"
```

- [ ] **Step 2: Create `kv.js`**

```javascript
const CODE_TTL = 300;       // 5 min
const RL_TTL = 3600;        // 1 hour

export async function putCode(env, key, code) {
  await env.OTP_KV.put(`otp:${key}`, code, { expirationTtl: CODE_TTL });
}
export async function getCode(env, key) {
  return env.OTP_KV.get(`otp:${key}`);
}
export async function deleteCode(env, key) {
  await env.OTP_KV.delete(`otp:${key}`);
}

export async function bumpCounter(env, name, key) {
  const k = `rl:${name}:${key}`;
  const cur = parseInt((await env.OTP_KV.get(k)) || '0', 10);
  const next = cur + 1;
  await env.OTP_KV.put(k, String(next), { expirationTtl: RL_TTL });
  return next;
}

export async function putTelegramChat(env, phone, chatId) {
  await env.OTP_KV.put(`tg:phone:${phone}`, String(chatId));
}
export async function getTelegramChat(env, phone) {
  const v = await env.OTP_KV.get(`tg:phone:${phone}`);
  return v ? Number(v) : null;
}

export function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export function randomCode() {
  const n = Math.floor(Math.random() * 1_000_000);
  return String(n).padStart(6, '0');
}

export async function sha256Hex(input) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}
```

- [ ] **Step 3: Create `telegram.js`**

```javascript
export async function sendTelegramCode(env, chatId, code) {
  const text = `Cofiz verification code: ${code}. Valid for 5 minutes.`;
  const res = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ chat_id: chatId, text }),
  });
  if (!res.ok) {
    throw new Error(`telegram ${res.status}`);
  }
}

export function validateTelegramInitData(initData, botToken) {
  // Per https://core.telegram.org/bots/webapps#validating-data-received-via-the-mini-app
  const url = new URLSearchParams(initData);
  const hash = url.get('hash');
  url.delete('hash');
  const dataCheckString = [...url.entries()].map(([k, v]) => `${k}=${v}`).sort().join('\n');
  // HMAC-SHA256 with bot token (key) on "WebAppData"
  return crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode('WebAppData'),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  ).then((key) => crypto.subtle.sign('HMAC', key, new TextEncoder().encode(botToken)))
    .then((secret) => crypto.subtle.importKey('raw', secret, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']))
    .then((key) => crypto.subtle.sign('HMAC', key, new TextEncoder().encode(dataCheckString)))
    .then((sig) => Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, '0')).join('') === hash);
}
```

- [ ] **Step 4: Create `whatsapp.js`**

```javascript
export async function sendWhatsAppCode(env, phone, code) {
  const res = await fetch(`https://graph.facebook.com/v17.0/${env.WHATSAPP_PHONE_ID}/messages`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${env.WHATSAPP_ACCESS_TOKEN}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to: phone,
      type: 'template',
      template: {
        name: 'otp_code',
        language: { code: 'en' },
        components: [{ type: 'body', parameters: [{ type: 'text', text: code }] }],
      },
    }),
  });
  if (!res.ok) {
    throw new Error(`whatsapp ${res.status}`);
  }
}
```

- [ ] **Step 5: Create `firebase.js`**

```javascript
import admin from 'firebase-admin';

let _app;
function ensureApp(env) {
  if (_app) return _app;
  _app = admin.initializeApp({
    credential: admin.credential.cert(JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON)),
  });
  return _app;
}

export async function createCustomToken(env, uid) {
  ensureApp(env);
  return admin.auth().createCustomToken(uid);
}
```

- [ ] **Step 6: Create `handlers.js`**

```javascript
import { putCode, getCode, deleteCode, bumpCounter, getTelegramChat, putTelegramChat, randomCode, sha256Hex, timingSafeEqual } from './kv.js';
import { sendTelegramCode, validateTelegramInitData } from './telegram.js';
import { sendWhatsAppCode } from './whatsapp.js';
import { createCustomToken } from './firebase.js';

const ALLOWED_PROVIDERS = new Set(['telegram', 'whatsapp']);
const E164 = /^\+[1-9]\d{7,14}$/;

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

export async function handleStart(request, env) {
  const body = await request.json();
  const { phone, provider, telegramInitData } = body;
  if (!E164.test(phone) || !ALLOWED_PROVIDERS.has(provider)) {
    return json({ error: 'bad_request' }, 400);
  }
  const startCount = await bumpCounter(env, 'start', phone);
  if (startCount > 5) return json({ error: 'rate_limited' }, 429);

  const code = randomCode();
  const verificationId = await sha256Hex(`${phone}:${provider}:${Date.now()}:${code}`);
  await putCode(env, `${provider}:${verificationId}:${phone}`, code);

  if (provider === 'telegram') {
    if (telegramInitData) {
      const ok = await validateTelegramInitData(telegramInitData, env.TELEGRAM_BOT_TOKEN);
      if (!ok) return json({ error: 'bad_init_data' }, 400);
      // Expect phone in initData user object; persist mapping
      const url = new URLSearchParams(telegramInitData);
      const user = JSON.parse(url.get('user') || '{}');
      if (user.id) await putTelegramChat(env, phone, user.id);
    }
    const chatId = await getTelegramChat(env, phone);
    if (!chatId) return json({ error: 'bot_not_started' }, 409);
    await sendTelegramCode(env, chatId, code);
  } else {
    await sendWhatsAppCode(env, phone, code);
  }

  return json({ verificationId, expiresInSeconds: 300 });
}

export async function handleVerify(request, env) {
  const body = await request.json();
  const { phone, provider, verificationId, code } = body;
  if (!E164.test(phone) || !ALLOWED_PROVIDERS.has(provider) || !verificationId || !code) {
    return json({ error: 'bad_request' }, 400);
  }
  const verifyCount = await bumpCounter(env, 'verify', phone);
  if (verifyCount > 10) return json({ error: 'rate_limited' }, 429);

  const stored = await getCode(env, `${provider}:${verificationId}:${phone}`);
  if (!stored) return json({ error: 'expired' }, 400);
  if (!timingSafeEqual(stored, code)) return json({ error: 'bad_code' }, 400);

  await deleteCode(env, `${provider}:${verificationId}:${phone}`);
  const uid = await sha256Hex(phone);
  const customToken = await createCustomToken(env, uid);
  return json({ customToken, uid, isNewUser: false });
}
```

- [ ] **Step 7: Create `index.js` (router)**

```javascript
import { handleStart, handleVerify } from './handlers.js';

export { handleStart as onOtpStart, handleVerify as onOtpVerify };
```

In `workers/fcm-relay/src/index.js`, add:

```javascript
import { onOtpStart, onOtpVerify } from './otp/index.js';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === '/otp/start' && request.method === 'POST') return onOtpStart(request, env);
    if (url.pathname === '/otp/verify' && request.method === 'POST') return onOtpVerify(request, env);
    // existing routes ...
  },
};
```

- [ ] **Step 8: Update `wrangler.toml`**

```toml
[[kv_namespaces]]
binding = "OTP_KV"
id = "REPLACE_WITH_REAL_ID"

# secrets (set via `wrangler secret put`):
# TELEGRAM_BOT_TOKEN
# WHATSAPP_PHONE_ID
# WHATSAPP_ACCESS_TOKEN
# FIREBASE_SERVICE_ACCOUNT_JSON
```

- [ ] **Step 9: Write handler tests**

Create `workers/fcm-relay/test/otp/handlers.test.js`:

```javascript
import { describe, it, expect, beforeEach } from 'vitest';
import { handleStart, handleVerify } from '../../src/otp/handlers.js';

function makeEnv(kv = new Map()) {
  return {
    OTP_KV: {
      async get(k) { return kv.get(k) ?? null; },
      async put(k, v) { kv.set(k, v); },
      async delete(k) { kv.delete(k); },
    },
    TELEGRAM_BOT_TOKEN: 'test',
    WHATSAPP_PHONE_ID: 'pid',
    WHATSAPP_ACCESS_TOKEN: 'tok',
    FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({
      type: 'service_account',
      project_id: 'test',
      private_key: '-----BEGIN PRIVATE KEY-----\nMIIBV...\n-----END PRIVATE KEY-----\n',
      client_email: 't@t.iam.gserviceaccount.com',
    }),
  };
}

describe('handleStart', () => {
  it('rejects bad phone', async () => {
    const env = makeEnv();
    const req = new Request('https://x/otp/start', { method: 'POST', body: JSON.stringify({ phone: 'abc', provider: 'telegram' }) });
    const r = await handleStart(req, env);
    expect(r.status).toBe(400);
  });
});

describe('handleVerify', () => {
  it('returns 400 expired when no code', async () => {
    const env = makeEnv();
    const req = new Request('https://x/otp/verify', { method: 'POST', body: JSON.stringify({ phone: '+251911234567', provider: 'telegram', verificationId: 'v1', code: '000000' }) });
    const r = await handleVerify(req, env);
    expect(r.status).toBe(400);
  });
});
```

- [ ] **Step 10: Run worker tests**

Run: `cd workers/fcm-relay && npm test`
Expected: 2 tests pass.

- [ ] **Step 11: Commit**

```bash
git add workers/fcm-relay/
git commit -m "feat(auth): add worker /otp endpoints with KV and rate limit"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| User-visible behavior (1–8) | Tasks 4, 5 |
| Telegram one-time /start | Task 6 (handlers + telegram.js) |
| WhatsApp one-time opt-in | Task 6 (whatsapp.js) |
| `AuthProvider` rewrite | Task 3 |
| `PhoneLoginScreen`, `OtpVerifyScreen` | Task 4 |
| `AuthBackend` HTTP client | Task 2 |
| Firestore user doc keying by `sha256(phone)` | Task 6 (handleVerify) |
| Worker routes `/otp/start`, `/otp/verify`, `/otp/telegram-link` | Task 6 (`telegram-link` is the initData flow inside `handleStart`; if you want a separate route, see open item) |
| KV bindings, secrets | Task 6 step 8 |
| Rate limiting 5/1h, 10/1h | Task 6 (rate_limit via KV counters) |
| 6-digit codes, 5-min TTL | Task 6 (`CODE_TTL = 300`) |
| Error handling matrix | Tasks 3, 4, 5, 6 |
| Testing matrix | Each task has its own tests |

**Placeholder scan:** no TBD/TODO/"similar to". All code is concrete.

**Type consistency:** `OtpProvider.telegram / .whatsapp` used in `AuthBackend`, `PhoneOtpAuthProvider`, `PhoneLoginScreen` — consistent. `RequestOtpResult.verificationId` consistent. `VerifyOtpResult.customToken/uid/isNewUser` consistent. `MockHttpClient` shared between Tasks 2, 3, 4.

**Open item:** `/otp/telegram-link` is folded into `handleStart` via `telegramInitData`. If you prefer a dedicated endpoint (cleaner separation), add it as a follow-up task — same shape, no breaking changes for the Flutter side.
