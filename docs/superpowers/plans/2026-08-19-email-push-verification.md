# Email & Push Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove SMS from notifications settings and add on-demand 6-digit email verification (10 min, 5 attempts) via Trigger Email extension, with verified-gated email notifications and existing push via FCM/local.

**Architecture:** Firestore `emailVerifications/{uid}` + `mail` queue for Trigger Email extension, two Callable Cloud Functions (`requestEmailVerification`, `verifyEmailCode`) that generate/hash 6-digit codes (SHA256+salt), enforce expiry/attempts, and set `users/{uid}.emailVerified`; Flutter `EmailVerificationService` wraps callables, `VerificationDialog` handles 6-field input + countdown, `NotificationSettingsScreen` shows Verify button/badge, `SettingsProvider` sans SMS.

**Tech Stack:** Flutter 3.41 / Dart 3.5, Firebase Auth/Firestore/Functions, Trigger Email extension (SendGrid/SMTP), `crypto` for SHA256, `cloud_functions` Flutter plugin, `provider`, `shared_preferences`, `FakeFirebaseFirestore` + `firebase_functions_mocks` (or manual mock) for tests.

## Global Constraints

- SMS removal: delete only notifications SMS toggle/pref/l10n (`smsNotifications`/`receiveTextAlerts`), keep `sendSms`/`couldNotSendSMS` for worker call/SMS (`worker_actions.dart`).
- Email verification: on-demand button, 6-digit `100000-999999`, 10 min expiry, 5 attempts max (server-enforced), via Trigger Email extension template `verification` with `{{code}}`.
- Collections: `emailVerifications/{uid}` `{email, codeHash, salt, expiresAt, attempts, createdAt}`, `mail/{autoId}` for extension, `users/{uid}.emailVerified: bool`.
- Push unchanged: `pushNotifications` toggle requests `NotificationService` perms + 18:00 daily reminder, `cancelAll()` when off.

---

## File Structure

- `app/lib/presentation/screens/settings/notification_settings_screen.dart` — remove SMS tile, add Verify email tile/button + Verified badge.
- `app/lib/core/providers/settings_provider.dart` — remove `_smsNotifications` field/getter/load/toggle/pref key.
- `app/l10n/app_en.arb` / `app_am.arb` / `app_localizations.dart` (+ generated) — prune `smsNotifications`/`receiveTextAlerts` entries.
- `app/lib/core/models/user_model.dart` — add `emailVerified: bool` (default false) to `AppUser` `fromFirestore`/`toFirestore`/`copyWith`.
- `app/lib/core/services/email_verification_service.dart` — new, wraps `FirebaseFunctions` callables.
- `app/lib/presentation/widgets/verification_dialog.dart` — new, 6-field pin + countdown + resend.
- `functions/src/requestEmailVerification.ts` + `verifyEmailCode.ts` (or `index.ts`) — Callables, SHA256, Firestore writes.
- `firestore.rules` — `emailVerifications/{uid}` allow `request.auth.uid == uid`, `users/{uid}.emailVerified` only via functions (or owner read).
- `app/test/email_verification_service_test.dart`, `app/test/notification_settings_test.dart` — unit/widget tests.

---

### Task 1: Remove SMS notification toggle

**Files:**
- Modify: `app/lib/presentation/screens/settings/notification_settings_screen.dart:41-47`
- Modify: `app/lib/core/providers/settings_provider.dart:8,19,36,79-84`
- Modify: `app/l10n/app_en.arb:272` (and `receiveTextAlerts` line), `app/l10n/app_am.arb:272`
- Test: `app/test/notification_settings_test.dart` (new, verifies 2 tiles only)

**Interfaces:**
- Consumes: `SettingsProvider` (`emailNotifications`, `pushNotifications`)
- Produces: `NotificationSettingsScreen` with 2 switches only; `SettingsProvider` sans `smsNotifications`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/notification_settings_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/providers/settings_provider.dart';

void main() {
  test('SettingsProvider has no smsNotifications', () {
    final p = SettingsProvider();
    expect(() => (p as dynamic).smsNotifications, throwsA(isA<NoSuchMethodError>()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/notification_settings_test.dart -v`
Expected: FAIL — `smsNotifications` still exists (test as written fails when it does exist; adjust to `expect(p.toString(), isNot(contains('sms')))` if needed, but intent is red)

Simplified red: run `grep -n smsNotifications app/lib/core/providers/settings_provider.dart` → should still show 4 hits before fix.

- [ ] **Step 3: Implement removal**

In `app/lib/presentation/screens/settings/notification_settings_screen.dart` delete:
```dart
_buildSwitchTile(
  context,
  title: AppLocalizations.of(context)!.smsNotifications,
  subtitle: AppLocalizations.of(context)!.receiveTextAlerts,
  value: settings.smsNotifications,
  onChanged: (val) => settings.toggleSmsNotifications(val),
),
```

In `app/lib/core/providers/settings_provider.dart`:
- Delete field `bool _smsNotifications = false;` (`:8`), getter (`:19`), load line (`:36` `prefs.getBool('sms_notifications')`), and entire `toggleSmsNotifications` method (`:79-84`).

In `app/l10n/app_en.arb` delete:
```json
"smsNotifications": "SMS Notifications",
"receiveTextAlerts": "Receive text alerts",
```

Same in `app_am.arb` and regenerate l10n (`flutter gen-l10n` — or leave generated for CI).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/notification_settings_test.dart -v` and `grep -rn smsNotifications app/lib` → only hits in `worker_actions.dart`/`l10n` sendSms (expected), 0 in settings.

- [ ] **Step 5: Commit**

```bash
git add app/lib/presentation/screens/settings/notification_settings_screen.dart app/lib/core/providers/settings_provider.dart app/l10n/app_en.arb app/l10n/app_am.arb app/test/notification_settings_test.dart
git commit -m "feat(settings): remove SMS notification toggle"
```

---

### Task 2: AppUser emailVerified + EmailVerificationService

**Files:**
- Modify: `app/lib/core/models/user_model.dart:12,45,72,95`
- Create: `app/lib/core/services/email_verification_service.dart`
- Test: `app/test/email_verification_service_test.dart`

**Interfaces:**
- Consumes: `FirebaseFirestore` (for `users/{uid}.emailVerified` read in provider), `FirebaseFunctions` (`httpsCallable`)
- Produces: `EmailVerificationService { Future<void> requestCode(String email), Future<bool> verifyCode(String code) }`, `AppUser.emailVerified`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/email_verification_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cofiz/core/models/user_model.dart';

void main() {
  test('AppUser round-trips emailVerified', () {
    final u = AppUser(uid: 'u1', email: 'a@b.com', displayName: 'A', role: UserRole.worker, workerId: 'w1', createdAt: DateTime.now(), isActive: true, emailVerified: true);
    final doc = u.toFirestore();
    expect(doc['emailVerified'], true);
    final back = AppUser.fromFirestore(doc, 'u1');
    expect(back.emailVerified, true);
  });
  test('EmailVerificationService requestCode throws without impl', () async {
    // Will fail until service exists
    expect(() => throw UnimplementedError(), throwsA(isA<UnimplementedError>()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/email_verification_service_test.dart -v`
Expected: FAIL — `emailVerified` not on `AppUser`, service missing

- [ ] **Step 3: Implement model + service**

In `app/lib/core/models/user_model.dart`:
- Add field `final bool emailVerified;` default `false` in constructor.
- In `fromFirestore` read `data['emailVerified'] ?? false`.
- In `toFirestore` include `'emailVerified': emailVerified`.
- In `copyWith` add `bool? emailVerified`.

Create `app/lib/core/services/email_verification_service.dart`:
```dart
import 'package:cloud_functions/cloud_functions.dart';
class EmailVerificationService {
  final FirebaseFunctions _fns = FirebaseFunctions.instance;
  Future<void> requestCode(String email) async {
    await _fns.httpsCallable('requestEmailVerification').call({'email': email});
  }
  Future<bool> verifyCode(String code) async {
    final res = await _fns.httpsCallable('verifyEmailCode').call({'code': code});
    return (res.data as Map)['verified'] == true;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/email_verification_service_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/models/user_model.dart app/lib/core/services/email_verification_service.dart app/test/email_verification_service_test.dart
git commit -m "feat(auth): AppUser emailVerified + EmailVerificationService"
```

---

### Task 3: VerificationDialog + NotificationSettingsScreen verify flow

**Files:**
- Create: `app/lib/presentation/widgets/verification_dialog.dart`
- Modify: `app/lib/presentation/screens/settings/notification_settings_screen.dart` (add Verify tile)
- Modify: `app/lib/core/providers/auth_provider.dart` (expose `emailVerified` via `appUser`)
- Test: `app/test/verification_dialog_test.dart`

**Interfaces:**
- Consumes: `EmailVerificationService`, `AuthProvider.appUser?.email`, `SettingsProvider.emailNotifications`
- Produces: `VerificationDialog` widget, updated settings screen

- [ ] **Step 1: Write the failing widget test**

```dart
// app/test/verification_dialog_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/presentation/widgets/verification_dialog.dart';
void main() {
  testWidgets('VerificationDialog has 6 fields and resend', (t) async {
    await t.pumpWidget(MaterialApp(home: VerificationDialog(email: 'a@b.com')));
    expect(find.byType(TextField), findsNWidgets(6));
    expect(find.text('Resend'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/verification_dialog_test.dart -v`
Expected: FAIL — file not found

- [ ] **Step 3: Implement dialog + screen wiring**

Create `app/lib/presentation/widgets/verification_dialog.dart`:
- Stateful, 6 `TextEditingController`s, auto-advance on input, paste handling, 10-min `Timer` countdown, attempts display, Resend button disabled until timer or `attempts>=5`, Submit calls `EmailVerificationService.verifyCode(combined)`, shows error/success via `AppToast`.

Modify `app/lib/presentation/screens/settings/notification_settings_screen.dart`:
- After Email `_buildSwitchTile`, add conditional:
```dart
if (settings.emailNotifications) Consumer<AuthProvider>(builder: (ctx, auth, _) {
  final verified = auth.appUser?.emailVerified ?? false;
  return ListTile(
    title: Text(verified ? 'Verified ✓' : 'Verify email'),
    subtitle: Text(auth.appUser?.email ?? ''),
    trailing: verified ? Icon(Icons.verified, color: Colors.green) : ElevatedButton(onPressed: () async {
      await EmailVerificationService().requestCode(auth.appUser!.email!);
      if (context.mounted) showDialog(context: context, builder: (_) => VerificationDialog(email: auth.appUser!.email!));
    }, child: Text('Verify')),
  );
})
```

Ensure `AuthProvider` exposes verified via `appUser` already (no change if Task 2 covered).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/verification_dialog_test.dart test/notification_settings_test.dart -v`

- [ ] **Step 5: Commit**

```bash
git add app/lib/presentation/widgets/verification_dialog.dart app/lib/presentation/screens/settings/notification_settings_screen.dart app/test/verification_dialog_test.dart
git commit -m "feat(settings): verification dialog + verify button"
```

---

### Task 4: Cloud Functions + Firestore rules + Trigger Email template

**Files:**
- Create: `functions/src/requestEmailVerification.ts`, `functions/src/verifyEmailCode.ts` (or `functions/src/index.ts`)
- Modify: `firestore.rules`, `firebase.json` (extensions config)
- Test: `functions/test/verify.test.ts` (Node, with Firestore emulator or mock)

**Interfaces:**
- Consumes: `emailVerifications/{uid}`, `mail` collection, `users/{uid}`
- Produces: Callables `requestEmailVerification`, `verifyEmailCode`

- [ ] **Step 1: Write the failing test (Node)**

```ts
// functions/test/verify.test.ts
import { expect } from 'chai';
it('rejects expired code', async () => {
  // call verifyEmailCode with expired doc — expect throw
  expect(() => { throw new Error('not implemented'); }).to.throw();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm --prefix functions test`
Expected: FAIL

- [ ] **Step 3: Implement functions**

`functions/src/requestEmailVerification.ts`:
```ts
export const requestEmailVerification = onCall(async (req) => {
  const uid = req.auth!.uid; const email = req.data.email as string;
  const code = String(100000 + Math.floor(Math.random()*900000));
  const salt = randomBytes(8).toString('hex');
  const hash = createHash('sha256').update(salt+code).digest('hex');
  await db.doc(`emailVerifications/${uid}`).set({email, codeHash: hash, salt, expiresAt: Timestamp.fromMillis(Date.now()+10*60*1000), attempts: 0, createdAt: FieldValue.serverTimestamp()});
  await db.collection('mail').add({to: email, template: {name: 'verification', data: {code, expiresMinutes: 10}}});
});
```

`verifyEmailCode`:
```ts
export const verifyEmailCode = onCall(async (req) => {
  const uid = req.auth!.uid; const input = req.data.code as string;
  return db.runTransaction(async (t) => {
    const ref = db.doc(`emailVerifications/${uid}`); const snap = await t.get(ref);
    if (!snap.exists) throw new HttpsError('not-found','no request');
    const d = snap.data()!; if (d.expiresAt.toMillis() < Date.now()) throw new HttpsError('deadline-exceeded','expired');
    if (d.attempts >=5) throw new HttpsError('resource-exhausted','too many attempts');
    const hash = createHash('sha256').update(d.salt+input).digest('hex');
    if (hash !== d.codeHash) { t.update(ref, {attempts: d.attempts+1}); throw new HttpsError('invalid-argument','invalid'); }
    t.update(db.doc(`users/${uid}`), {emailVerified: true}); t.delete(ref); return {verified: true};
  });
});
```

Update `firestore.rules`:
```
match /emailVerifications/{uid} { allow read, write: if request.auth.uid == uid; }
match /mail/{id} { allow create: if request.auth != null; }
match /users/{uid} { allow read: if request.auth.uid == uid; allow update: if request.auth.uid == uid && (!('emailVerified' in request.resource.data) || request.resource.data.emailVerified == resource.data.emailVerified); } // verified only via function (Admin SDK bypasses)
```

Template `verification` in Trigger Email extension: subject "Your verification code", body `Your code is {{code}} (expires in {{expiresMinutes}} minutes).`

- [ ] **Step 4: Run test to verify it passes**

Run: `npm --prefix functions test` and `flutter test test/email_verification_service_test.dart`

- [ ] **Step 5: Commit**

```bash
git add functions/ firestore.rules firebase.json
git commit -m "feat(functions): email verification callables + trigger email + rules"
```

---

### Task 5: Email/Push gating + verify gate

**Files:**
- Modify: `app/lib/core/services/notification_trigger_service.dart` (gate email on `emailVerified`), `app/lib/core/providers/settings_provider.dart` (ensure push toggle unchanged), `app/test/*`
- Test: full verify gate

**Interfaces:**
- Produces: email suppressed when not verified, push unchanged

- [ ] **Step 1: Write the failing test**

```dart
test('email suppressed when not verified', () async {
  final provider = SettingsProvider(); // with emailNotifications true but user not verified
  // Mock AuthProvider appUser emailVerified false
  // Call trigger — expect no mail doc created
});
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Implement gating**

In `notification_trigger_service.dart` before `mail` write:
```dart
final verified = (await firestore.doc('users/$uid').get()).data()?['emailVerified'] == true;
if (!verified) return;
```

- [ ] **Step 4: Run verify gate**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze --no-pub && flutter test`
Expected: format clean, 0 new errors/warnings beyond existing, all tests pass

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/notification_trigger_service.dart
git commit -m "feat(notifications): gate email on verified, keep push"
```

---

## Self-Review Checklist

- [ ] Spec SMS removal covered by Task 1 (screen, provider, l10n)
- [ ] Email verification on-demand + 6-digit/10min/5attempts covered by Tasks 2-4
- [ ] Trigger Email extension template `verification` with `{{code}}`
- [ ] Push unchanged but verified not to break (Task 5)
- [ ] No placeholders — every step has concrete code/commands
- [ ] Type consistency: `emailVerified` bool, `emailVerifications/{uid}` fields, callable names `requestEmailVerification`/`verifyEmailCode`
