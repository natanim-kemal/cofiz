# Email & Push Notifications with 6-Digit Verification — Design

Date: 2026-08-19
Status: Approved (brainstorming)
Scope: Remove SMS notification toggle; add on-demand 6-digit email verification (Firebase Trigger Email extension, 10 min expiry, 5 attempts) and gate email/push notifications on verification/prefs.
Related code: `lib/presentation/screens/settings/notification_settings_screen.dart`, `lib/core/providers/settings_provider.dart`, `lib/core/services/notification_service.dart`, `lib/core/services/fcm_service.dart`, `lib/core/services/email_verification_service.dart` (new), `functions/` (callable), `l10n/*`, Firestore `emailVerifications` + `mail`.

## 1. Context

Notifications settings currently exposes three toggles: Email, Push, SMS (`notification_settings_screen.dart:41-47`, `settings_provider.dart:8,79-84`). SMS is a stored pref only (`sms_notifications`) with no domain integration beyond call/SMS launch via `worker_actions.dart`. L10n has `smsNotifications`/`receiveTextAlerts` (`app_en.arb:272`). Requirement: remove SMS from notifications page. Add reliable Email (gated on verification) and keep Push (FCM + local daily reminder already in `settings_provider.dart:59-77`). Email verification is on-demand (button), 6-digit code, 10 min TTL, 5 attempts, sent via Firebase Extension "Trigger Email" (SendGrid/SMTP).

## 2. Goals / Non-goals

Goals:
- No SMS toggle or pref in notifications settings.
- On-demand "Verify email" flow: send 6-digit code via Trigger Email extension to the user's account email, input to confirm, mark verified.
- Email notifications for domain events only when verified + pref on.
- Push notifications remain via existing FCM/local stack, gated on pref.

Non-goals:
- Changing worker call/SMS launch (`worker_actions.dart`, `worker_detail_screen`) — keep.
- Receipt upload / transaction logic — out of scope.
- Building a custom SMTP service — use Trigger Email extension.

## 3. Chosen Approach

**A. Firestore `emailVerifications` + Trigger Email extension + Callable Functions (Recommended)**

Client calls Callable `requestEmailVerification(email)` — function generates 6-digit `100000-999999`, hashes (SHA256 + salt), writes `emailVerifications/{uid}` `{email, codeHash, salt, expiresAt: now+10m, attempts: 0, verified: false, createdAt}` and writes `mail/{autoId}` `{to: email, template: {name: 'verification', data: {code}}}` for extension. Client shows 6-field dialog. Submit calls `verifyEmailCode(uid, input)` — function validates expiry, `attempts<5`, hash compare, on success sets `users/{uid}.emailVerified=true` and deletes verification doc, else increments `attempts`. Rejected alternatives: B custom SMTP function (more ops), C Auth link (not 6-digit).

Rationale: client never handles plaintext code secret, 5-attempt limit enforced atomically server-side, leverages chosen extension.

## 4. Architecture

### 4.1 SMS Removal

- `notification_settings_screen.dart` — delete `_buildSwitchTile` for `smsNotifications` (`:43-47`).
- `settings_provider.dart` — delete field `_smsNotifications` (`:8`), getter `smsNotifications` (`:19`), load `prefs.getBool('sms_notifications')` (`:36`), `toggleSmsNotifications` (`:79-84`).
- `SharedPreferences` key `sms_notifications` orphaned — ignored; no migration.
- L10n prune: `smsNotifications` + `receiveTextAlerts` from `app_en.arb:272`, `app_am.arb:272`, `app_localizations.dart:1463`, `app_localizations_en.dart:731`, `app_localizations_am.dart:727`. Keep `sendSms`/`couldNotSendSMS` (worker call/SMS, not notifications).

### 4.2 Email Verification

**Collections:**
- `emailVerifications/{uid}` — `{email: string, codeHash: string, salt: string, expiresAt: Timestamp, attempts: number (0..5), createdAt: Timestamp}`
- `mail/{autoId}` — `{to: string, template: {name: 'verification', data: {code: string, expiresMinutes: 10}}}`
- `users/{uid}` — add `emailVerified: boolean` (default false).

**Services (new):**
- `lib/core/services/email_verification_service.dart`
  - `Future<void> requestCode()` — calls `functions.httpsCallable('requestEmailVerification')`
  - `Future<bool> verifyCode(String input)` — calls `verifyEmailCode`, returns true/false, surfaces `attemptsLeft`/`expired` via exception.

**Functions (`functions/`):**
- `requestEmailVerification` (callable, auth required): validate `request.auth.uid` matches target, rate-limit, generate code, hash, write verification doc, write `mail` doc.
- `verifyEmailCode` (callable): transaction read verification doc, check `expiresAt`, `attempts<5`, hash compare, on success update `users/{uid}.emailVerified=true`, delete doc, on fail `attempts++`.

**Security Rules:**
- `emailVerifications/{uid}` — `allow read, write: if request.auth.uid == uid`
- `mail` — `allow create: if request.auth != null` (or function-only via Admin SDK); no client read.
- `users/{uid}` — `emailVerified` writable only by `verifyEmailCode` function (rules check `request.auth.token.admin` or function service account).

### 4.3 UI Flow

**Entry:** `NotificationSettingsScreen` under Email switch:
- If `appUser.emailVerified != true` (read from `AuthProvider.appUser` + Firestore `users/{uid}.emailVerified`) and `emailNotifications` on → show tile/button "Verify email" (disabled if email missing).
- If verified → badge "Verified ✓" (no button).

**Dialog `VerificationDialog` (new `lib/presentation/widgets/verification_dialog.dart`):**
- 6 `TextField`s (auto-advance, paste support) or single `PinCodeTextField`, 10-min countdown `mm:ss`, attempts counter, "Resend" disabled until countdown or 5 fails.
- Request code → toast "Code sent to your email", open dialog.
- Submit → `verifyCode` → success toast, badge updates, email gate opens; failure shows "Invalid (N left)", "Expired, resend", or "Too many attempts, resend".

Resend generates new code and resets `attempts`/`expiresAt`.

### 4.4 Email + Push Wiring

- **Email notifications for domain events:** `NotificationTriggerService` / transaction/income handlers, before writing `mail` for event emails, check `SettingsProvider.emailNotifications && users/{uid}.emailVerified == true`; if not verified, suppress and optionally show "Verify email to enable" in settings.
- **Push:** keep `settings_provider.dart:59-77` — `togglePushNotifications` requests `NotificationService.requestPermissions()` and schedules daily 18:00 reminder, else `cancelAll()`. `FCMService` token/topics unchanged. SMS removal does not affect.

### 4.5 Edge Cases

- Resend while code active → new code invalidates old.
- Email changed → clear `emailVerified=false`, require re-verify.
- Offline: request/verify require network — show "Connect to verify".
- 5 attempts exhausted → must resend.

### 4.6 Testing

- Unit: `EmailVerificationService` hash/encode, `verifyCode` attempt/expiry logic with `FakeFirebaseFirestore` + function mocks; `SettingsProvider` sans SMS.
- Widget: `VerificationDialog` paste, countdown, resend throttle, success/failure toasts.
- Manual: send code, check `mail` doc queued, receive email, verify, check `emailVerified`, check email notification gated.

### 4.7 Rollout

- Install/configure Trigger Email extension with `verification` template `{{code}} expires in 10 minutes`.
- Add `emailVerifications` collection, deploy 2 callables, update Firestore rules, deploy.
- No data migration; old `sms_notifications` pref ignored.

## 5. File Changes (planned)

- Modify: `lib/presentation/screens/settings/notification_settings_screen.dart`, `lib/core/providers/settings_provider.dart`, `l10n/app_en.arb`, `l10n/app_am.arb`, `l10n/app_localizations.dart` (+ generated), maybe `lib/core/providers/auth_provider.dart` to expose `emailVerified`.
- Create: `lib/core/services/email_verification_service.dart`, `lib/presentation/widgets/verification_dialog.dart`, `functions/src/requestEmailVerification.ts`, `functions/src/verifyEmailCode.ts` (or single file), tests `test/email_verification_test.dart`, `test/notification_settings_test.dart`.

## 6. Open Questions (Resolved)

- Trigger: on-demand verify button (confirmed).
- Email sender: Trigger Email extension (confirmed).
- Code policy: 10 min, 5 attempts (confirmed).
