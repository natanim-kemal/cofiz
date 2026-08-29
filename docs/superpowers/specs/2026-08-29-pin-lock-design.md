# Feature: PIN Lock with 2-Minute Idle Timeout

**Date:** 2026-08-29
**Status:** Approved design — ready to plan
**Target codebase:** `app/` (Cofiz Flutter app)
**Replaces:** Two-factor authentication in the Settings page
**Co-dependency:** Feature #1 (Phone-OTP Login) — "Forgot PIN" recovery uses the OTP flow.

## Goal

Lock the app after 2 minutes of inactivity with a 6-digit PIN the user sets on first login. Coexists with the existing biometric lock as a parallel option.

## Out of scope

- Configurable PIN length (always 6 digits in v1).
- Configurable idle duration (always 2 minutes in v1; constant in `kIdleLockDuration`).
- Per-screen lock behavior.
- Remote wipe.

## User-visible behavior

### First login after feature ships

1. After successful phone-OTP sign-in, the app shows a **mandatory** "Create your PIN" screen.
2. User enters a 6-digit PIN, then re-enters to confirm. Both must match and be exactly 6 digits.
3. On success, the user is taken to the home screen.
4. PIN can be changed or removed from Settings → "PIN lock" (same row that today reads "Two-factor authentication", same icon, relabeled).

### Idle lock

- Any touch anywhere in the app resets a 2-minute timer.
- On timer expiry, the app pushes a full-screen `PinLockScreen` route above everything.
- On `AppLifecycleState.paused` (background), the app locks immediately, regardless of timer.
- On `AppLifecycleState.resumed`, if locked, the `PinLockScreen` is shown.

### Lock screen UX

- App logo + "Enter PIN" title.
- 6-dot indicator (filled as user types) on top of a numeric keypad.
- "Forgot PIN?" link → signs the user out → routes to `PhoneLoginScreen`. After successful re-auth, PIN is cleared and the user is prompted to set a new one on next entry.

### Settings → PIN lock

Replaces the existing "Two-factor authentication" entry. Keeps the same icon. Contains:

- "Set PIN" (if none) / "Change PIN" (if set) / "Remove PIN" (if set).
- "Lock now" button (testing).
- "Auto-lock when idle" toggle (default on).
- Read-only line: "Locks after 2 minutes of inactivity."

### Coexistence with biometric

- If the user has both biometric and PIN set, the lock screen shows: numeric keypad + a "Use biometric" button (icon = fingerprint).
- Tapping the button calls `LocalAuth.authenticate(...)`.
- Either path unlocks.

## Architecture

### 1. `lib/core/services/pin_service.dart` (new)

Responsibilities:
- `setPin(String pin)` — generate 16-byte salt, hash with PBKDF2-HMAC-SHA256 (100,000 iterations, 32-byte output), store `{ salt, hash, iterations, length: 6 }` in `flutter_secure_storage` under key `pin_lock_v1`.
- `verifyPin(String pin)` — load the salt, hash the entered PIN, constant-time compare to the stored hash.
- `hasPin()` — boolean.
- `clearPin()` — remove the key.
- `changePin(String oldPin, String newPin)` — verify old, set new.

Uses `crypto` (already in the project — `flutter_secure_storage` depends on it transitively) for PBKDF2.

### 2. `lib/core/services/idle_lock_service.dart` (new)

Responsibilities:
- Listens to a `Listener` wrapping the `MaterialApp`'s `home` widget via `WidgetsBinding.instance.addObserver` and a `NotificationListener<ScrollNotification>` plus a `RawKeyboardListener` fallback.
- Exposes `resetTimer()` which is debounced.
- On timer expiry, calls `LockStateProvider.lock()`.
- Configurable `kIdleLockDuration = Duration(minutes: 2)`.
- Pause/resume hook into `WidgetsBindingObserver.didChangeAppLifecycleState`.

### 3. `lib/core/providers/lock_state_provider.dart` (new)

`ChangeNotifier` with states: `unlocked`, `locked`, `awaitingFirstSetup`.

Methods: `lock()`, `unlock()`, `promptForSetup()`.

### 4. `lib/presentation/screens/auth/pin_lock_screen.dart` (new)

Full-screen route. Pushes via `Navigator.push` with a transparent route so it covers everything. Localized keypad.

### 5. `lib/presentation/screens/auth/create_pin_screen.dart` (new)

Two-step: enter PIN, confirm PIN. Used on first login and from "Change PIN".

### 6. Settings page changes

- File: `lib/presentation/screens/settings/settings_screen.dart` (and the 2FA section widget).
- Replace the existing 2FA tile with a "PIN lock" tile using the **same icon** as before.
- New sub-screen `lib/presentation/screens/settings/pin_lock_settings_screen.dart` for set/change/remove/lock-now.

### 7. App initialization (`lib/main.dart`)

- After login, before showing home, check `PinService.hasPin()`. If false, push `CreatePinScreen`. (This is the "forced on first login" requirement.)
- `IdleLockService` is constructed at app start and bound to the `MaterialApp` body.

## Data model

All data is on-device. Nothing in Firestore.

| Storage | Key | Value |
|---|---|---|
| `flutter_secure_storage` | `pin_lock_v1` | JSON: `{ "salt": "<base64>", "hash": "<base64>", "iterations": 100000, "length": 6 }` |
| `flutter_secure_storage` | `pin_lock_enabled_v1` | `"true"` / `"false"` (default `"true"` when a PIN is set) |
| `shared_preferences` | `lock_idle_enabled_v1` | `"true"` (default) / `"false"` |

We split the "is the auto-lock on" toggle from "is a PIN set" so a user can disable the idle lock but keep the PIN for a manual "Lock now" — or vice versa.

## Security considerations

- PIN hash uses PBKDF2 with 100,000 iterations (OWASP 2023 recommendation for SHA-256).
- Constant-time compare to prevent timing attacks.
- Salt is 16 random bytes per PIN. On "Change PIN" we re-derive with a fresh salt.
- `flutter_secure_storage` is iOS Keychain / Android Keystore-backed. Already in the project.
- On biometric failure, the user is **not** given an option to "skip" — they must enter the PIN. After 5 failed PIN attempts, the lock screen shows "Too many attempts. Sign in again to continue." which routes through OTP.
- PIN never leaves the device, never logged, never sent to the worker.
- On `LockStateProvider.lock()`, the app does **not** clear any sensitive in-memory state beyond pushing the lock screen.

## Error handling

| Failure | UX |
|---|---|
| User enters wrong PIN | Single dot shake animation, "Incorrect PIN. Try again." |
| 5 wrong attempts | "Too many attempts. Sign in again." → logout |
| Biometric unavailable | Hide the biometric button, show only numeric keypad |
| Biometric lockout (too many biometric failures) | Show "Use PIN" only |
| `flutter_secure_storage` write fails | Toast: "Could not save PIN. Try again."; do not advance |
| `IdleLockService` timer fire while on a critical screen (e.g. mid-OTP) | Lock screen pushes above; OTP state preserved in `AuthProvider` |

## Testing

- **Unit:** `PinService` round-trips (set/verify/change/clear); `LockStateProvider` transitions.
- **Widget:** `PinLockScreen` (golden), `CreatePinScreen` (golden, EN + Amharic).
- **Integration:** `IdleLockService` test using a fake clock.
- **Manual:** lock after timeout, lock on background, lock now, forgot PIN via OTP, change PIN, remove PIN, biometric fallback (Android emulator + iOS sim).

## Open questions

- Should there be a "Too many attempts" cooldown (e.g., 30s lockout before retry)? **Default: yes — 30s after 5 wrong attempts, escalating to "sign in again" after 10.** Defer to implementation planning.
- Should the "Auto-lock when idle" toggle also affect the `AppLifecycleState.paused` lock? **Default: no — background lock is always on.** Defer to implementation planning.
