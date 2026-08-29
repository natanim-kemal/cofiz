# Feature: Phone-OTP Login via Telegram and WhatsApp

**Date:** 2026-08-29
**Status:** Approved design — ready to plan
**Target codebase:** `app/` (Cofiz Flutter app)
**Replaces:** Email/password authentication

## Goal

Replace email/password sign-in with phone-number sign-in using one-time codes sent over Telegram or WhatsApp. The user picks the channel on the login screen.

## Out of scope

- SMS fallback (no Twilio, no Firebase Phone Auth).
- Social providers beyond Telegram/WhatsApp.
- Multi-factor auth flows (PIN lock is the second factor — see feature #2).
- Telegram Login Widget (popup-based; does not fit mobile flow).

## User-visible behavior

1. App opens. New `PhoneLoginScreen` replaces the email/password form.
2. User picks **Telegram** or **WhatsApp** at the top (segmented control).
3. User enters phone number in E.164 format. Country code picker defaults to `+251` (Ethiopia) since the app is bilingual EN/Amharic; can be overridden.
4. User taps **Send code**.
5. App shows the OTP screen with a 6-digit input and a 60-second resend cooldown.
6. Within ~5 seconds the user receives a message on the chosen channel containing the code.
7. User enters the code → app signs in. On first sign-in, a Firestore `users/{uid}` doc is created with `phone`, `role`, `displayName`, `createdAt`, `lastLoginAt`. On subsequent sign-ins `lastLoginAt` updates.
8. If the user already has an email/password account, the migration path is "enter old email → receive a link by email → tap to confirm phone link" (one-time), then the password option disappears for that account. New users skip this step.

### Telegram one-time /start instructions

A user must have opened our Telegram bot at least once before we can message them. The login screen shows a banner with a `t.me/<bot>` deep link and the text "Tap to open the bot, press Start, then return to the app." We do not retry automatically; the user comes back and taps Send code again.

### WhatsApp one-time opt-in

For WhatsApp Business Cloud API, the user must trigger the opt-in template. The login screen shows a deep link `https://wa.me/<phone>?text=START` and the same instructional banner.

## Architecture

### 1. Flutter app

**New / changed files:**

- `lib/core/providers/auth_provider.dart` — rewrite around `PhoneOtpAuthProvider` with state: `unauthenticated`, `awaitingCode`, `verifying`, `authenticated`, `error`.
- `lib/presentation/screens/auth/phone_login_screen.dart` — new.
- `lib/presentation/screens/auth/otp_verify_screen.dart` — new.
- `lib/presentation/screens/auth/login_screen.dart` — deleted (or reduced to a thin shim that delegates to `PhoneLoginScreen`).
- `lib/core/services/auth_backend.dart` — new, wraps HTTP calls to the worker.
- `lib/core/services/auth_backend_firebase.dart` — new, wraps `FirebaseAuth.instance.signInWithCustomToken`.
- `lib/l10n/app_localizations*.dart` — add new strings (`sendCode`, `resendCode`, `providerTelegram`, `providerWhatsApp`, `botOptInBannerTitle`, `botOptInBannerBody`, `enterPhoneNumber`, `invalidPhoneNumber`).

**State machine:**

```
PhoneLoginScreen submit
  → AuthBackend.requestOtp(phone, provider)
       success → push OtpVerifyScreen
       failure → show error
OtpVerifyScreen submit
  → AuthBackend.verifyOtp(phone, provider, verificationId, code)
       success → AuthBackendFirebase.signInWithCustomToken(token)
                  → navigate to home
       failure → show error, allow retry up to 5 times
       resend   → AuthBackend.requestOtp(...) (rate-limited)
```

**Rate limiting (client side, in addition to server):**
- 1 OTP per phone per 60s; 5 per phone per hour.
- Cooldown timer is shown under the Send button.

**Firestore user doc:**
- Keyed by `uid = sha256(phone)` — 64 hex chars, used as the document id.
- Fields: `phone`, `role` (`admin` | `collector` | `viewer`), `displayName`, `createdAt`, `lastLoginAt`, `telegramChatId?`, `whatsappPhone?`.
- An index `users.phone` (already likely there for the existing email login) is reused.

**Migration of existing email/password users:**
- On first OTP sign-in with a phone that matches an existing `users` doc by `email == sha256(phone)[:8]@phone.local` (a synthetic mapping) — **we do NOT do this**. The user-facing flow is: existing users tap "I already have an account" → enter their old email → receive a one-time link by SMS (we send via our new worker to the phone on file) → tap the link → confirms phone → password option hidden.
- **This is the only path that requires the existing email to still be reachable.** The product call is to keep email reachable for the migration window and remove it in a follow-up release.

### 2. Cloudflare Worker (`workers/fcm-relay`)

**New routes:**

- `POST /otp/start` — body `{ phone, provider, telegramChatId? }`. Generates a 6-digit code, stores it in Cloudflare KV under `otp:<provider>:<phone>` with a 5-minute TTL, and dispatches:
  - Telegram: calls `https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/sendMessage` with `chat_id` (resolved from a `tg:phone:<e164>` KV entry) and the text `"<AppName> verification code: <CODE>. Valid for 5 minutes."`.
  - WhatsApp: calls `https://graph.facebook.com/v17.0/<PHONE_ID>/messages` with the body `{ "messaging_product": "whatsapp", "to": "<phone>", "type": "template", "template": { "name": "otp_code", "language": { "code": "en" }, "components": [ { "type": "body", "parameters": [ { "type": "text", "text": "<CODE>" } ] } ] } }`.
- `POST /otp/verify` — body `{ phone, provider, verificationId, code }`. Reads the code from KV, constant-time compares, and on success:
  - Calls Firebase Admin SDK `createCustomToken(sha256(phone))` using the service account stored as a Worker secret `FIREBASE_SERVICE_ACCOUNT_JSON`.
  - Returns `{ customToken, uid, isNewUser }`. `isNewUser` is `true` when the `users/{uid}` doc didn't exist at verification time.
- `POST /otp/telegram-link` — body `{ phone, initData }`. Called after the user taps Start on the bot. The worker validates the `initData` against the bot token (per Telegram's HMAC-SHA256 spec) and stores `tg:phone:<e164> → chatId` in KV.

**New secrets / config:**

- `TELEGRAM_BOT_TOKEN` — set with `wrangler secret put`.
- `WHATSAPP_PHONE_ID`, `WHATSAPP_ACCESS_TOKEN` — set with `wrangler secret put`.
- `FIREBASE_SERVICE_ACCOUNT_JSON` — set with `wrangler secret put`.
- `KV` namespace — new binding `OTP_KV` for codes and `tg:phone:*` mappings.

**Rate limiting (server):**

- `OTP_KV` counters: `rl:start:<phone>` and `rl:verify:<phone>` with 1-hour TTL.
- Reject when `rl:start:<phone> > 5` or `rl:verify:<phone> > 10` with `429`.

### 3. Bot-side onboarding

- The Telegram bot's `/start` command captures the user's phone number from the deep-link payload `?start=<phone>`, so the user can be linked to a phone in one tap. Login screen flow: enter phone → "Open Telegram" deep link with `?start=<e164>` → user taps Start in the bot → bot's webhook writes `tg:phone:<e164> → chatId` to KV.
- For WhatsApp, we send a freeform opt-in template first; once they reply, the webhook records `wa:phone:<e164>`.

## Data model

| Collection / KV | Key | Fields |
|---|---|---|
| Firestore `users` | `uid = sha256(phone)` | `phone`, `role`, `displayName`, `createdAt`, `lastLoginAt`, `telegramChatId?`, `whatsappPhone?` |
| Firestore `users` | (deleted) | `email`, `passwordHash`, `emailVerified` — these fields are removed from new docs and the email/password login screen is gone |
| Cloudflare KV `OTP_KV` | `otp:<provider>:<phone>` | string of 6 digits, TTL 300s |
| Cloudflare KV `OTP_KV` | `tg:phone:<e164>` | telegram `chat_id` (long) |
| Cloudflare KV `OTP_KV` | `wa:phone:<e164>` | boolean — opt-in received |
| Cloudflare KV `OTP_KV` | `rl:start:<phone>` | counter, TTL 3600 |
| Cloudflare KV `OTP_KV` | `rl:verify:<phone>` | counter, TTL 3600 |

## Security considerations

- Codes are 6 digits → 1M space. With 5-attempt limit and 5-min TTL, brute force is bounded.
- Codes are stored in KV (not Firestore) so they are wiped on TTL.
- `verifyOtp` uses `crypto.timingSafeEqual` for the comparison.
- Bot `/start` payload validates `initData` HMAC against the bot token.
- Firebase service account JSON is stored as a Worker secret — never logged.
- Custom token lifetime is 1 hour; the app uses `FirebaseAuth.instance.signInWithCustomToken`, after which the standard Firebase token rotation takes over.
- The `uid = sha256(phone)` is fine because phone is the *only* identity; collision risk is acceptable for our user volume.

## Error handling

| Failure | UX |
|---|---|
| Phone number malformed | Inline validation, button disabled |
| Telegram bot not started | Banner stays; Send Code button retries, shows "Open Telegram" until chatId is registered |
| WhatsApp opt-in not received | Same banner pattern |
| Code expired | "Code expired. Tap to resend" |
| Wrong code 5 times | "Too many attempts. Try again in 1 hour." |
| Network failure on `requestOtp` | Toast with retry |
| Firebase custom token rejected | Sign out and route to `PhoneLoginScreen` with error toast |

## Testing

- **Unit:** `AuthBackend` mocked, state-machine transitions.
- **Worker:** integration tests against `wrangler dev` — fake KV, fake Telegram/WhatsApp endpoints, real Firebase Admin SDK against an emulator.
- **Widget:** golden tests for `PhoneLoginScreen` and `OtpVerifyScreen` in EN and Amharic.
- **Manual:** real Telegram bot, real WhatsApp sandbox number, end-to-end on iOS and Android.

## Roll-out

1. Ship to internal company first (1 business, ~5 users).
2. Cutover: existing users go through the email → phone-link flow once.
3. After 30 days, remove the email-link flow and any remaining email/password UI.

## Open questions

- For the migration window, who sends the email "click to link your phone" — Firebase Trigger Email extension, or our worker? Default: worker (`POST /otp/migration-email`) for symmetry, but the user may prefer to keep that on Firebase. **Defer to implementation planning.**
- The Amharic-localized OTP message — translations need a native speaker review. **Defer to implementation planning.**
