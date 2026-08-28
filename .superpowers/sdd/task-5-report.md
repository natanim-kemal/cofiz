# Task 5 Report: Worker Cron + Relay Env via Firestore (remove dart-define)

## What was implemented

Task 5 of `docs/superpowers/plans/2026-08-28-ping-and-nudge-notifications.md` + env migration (no --dart-define needed).

### 1. `app/lib/core/config/relay_config.dart:1-76`
Migrated from pure `String.fromEnvironment` to Firestore runtime with dart-define backward compat:

```dart
static const String _envRelayUrl = String.fromEnvironment('RELAY_URL');
static const String _envRelaySecret = String.fromEnvironment('RELAY_SECRET');
static String _relayUrl = _envRelayUrl;
static String _relaySecret = _envRelaySecret;
static bool _initialized = false;
static String get relayUrl => _relayUrl;
static String get relaySecret => _relaySecret;
static bool get isConfigured => relayUrl.isNotEmpty && relaySecret.isNotEmpty;

static Future<void> init({FirebaseFirestore? firestore, bool force=false}) async {
  if (_initialized && !force) return;
  final doc = await (firestore ?? FirebaseFirestore.instance)
      .collection('settings').doc('app').get().timeout(2s);
  if (doc.exists) {
    final url = doc.data()?['relayUrl']; // stringValue
    final secret = doc.data()?['relaySecret'];
    if (url is String && url.isNotEmpty) _relayUrl = url;
    if (secret is String && secret.isNotEmpty) _relaySecret = secret;
  }
  _initialized = true; // fallback to env on catch/timeout
}
static Future<void> ensureInitialized({FirebaseFirestore? firestore}) async {
  if (!_initialized) await init(firestore: firestore);
}
@visibleForTesting setForTest/resetForTest/isInitialized
```

- Keeps `String.fromEnvironment` fallback (env still works if Firestore unavailable).
- Caches in-memory after first fetch; idempotent unless `force:true`.
- Empty strings in Firestore do not overwrite non-empty env.

### 2. `app/lib/core/services/ping_service.dart:88-109`
Uses runtime config:
```dart
String relayUrl = _relayUrlOverride ?? RelayConfig.relayUrl;
String relaySecret = _relaySecretOverride ?? RelayConfig.relaySecret;
if (_relayUrlOverride == null || _relaySecretOverride == null) {
  await RelayConfig.ensureInitialized(firestore: _firestore);
  relayUrl = _relayUrlOverride ?? RelayConfig.relayUrl;
  relaySecret = _relaySecretOverride ?? RelayConfig.relaySecret;
}
```
Respects override in tests; otherwise ensures Firestore fetch before fan-out.

### 3. `app/lib/core/services/offline_sync_service.dart:825-846`
```dart
try { await RelayConfig.ensureInitialized(firestore: firestore); } catch (_) {}
if (!RelayConfig.isConfigured) { debugPrint('[Relay] SKIPPED ... Set settings/app relayUrl/relaySecret or build with --dart-define=...'); return; }
```
Message updated to mention Firestore path while preserving dart-define hint.

### 4. `app/lib/main.dart:4,85-108`
- Added import `core/config/relay_config.dart:4`.
- `_initializeNetworkServices()` now includes `RelayConfig.init()` in `Future.wait` and a post-wait `ensureInitialized()` so Firestore-sourced relay is available without `--dart-define`, deferred via `addPostFrameCallback` (existing pattern).

### 5. `workers/fcm-relay/src/index.js:133-418`
Added `scheduled` handler every 30 min + helpers, keeping existing `fetch` 404→null fix:

**Exported pure helpers for TDD:**
- `parseTimeToMinutes('20:00')->1200` validates HH:mm
- `isInWindow('20:00', nowMin)` true only at base+0/+30/+60
- `getAddisNow(date)` via `toLocaleString('en-US',{timeZone:'Africa/Addis_Ababa'})`
- `formatAddisDate(addisNow)` YYYY-MM-DD
- `getAddisDayBoundsMs(addisNow)` computes `{startMs, endMs}` as Addis midnight UTC (Date.UTC(y,m,d)-3h)

**Firestore REST helpers:** `decodeField/decodeDoc/encodeField/encodeFields/getDoc/setDoc/runQuery/getUsersByRole/hasTransactionToday/createNotificationDoc`

**Scheduled logic:**
```js
async scheduled(event, env) {
  const accessToken = await getAccessToken(env);
  const cfg = await getDoc(env, accessToken, 'settings/app') || {};
  const addisNow = getAddisNow(event?.scheduledTime ? new Date(event.scheduledTime) : Date.now());
  const nowMin = addisNow.getHours()*60+addisNow.getMinutes();
  const todayStr = formatAddisDate(addisNow);

  // Nightly admin nudge
  if (cfg.reminderEnabled !== false && cfg.adminReminderTime) {
    if (isInWindow(cfg.adminReminderTime, nowMin)) {
      if (cfg.lastReminderDate !== todayStr) {
        const hasTx = await hasTransactionToday(env, accessToken, addisNow); // startMs/endMs range query
        if (!hasTx) {
          const admins = await getUsersByRole(env, accessToken, 'admin');
          for (uid of admins) { tok=await getFcmToken(...); if(tok) await sendPush(...,{title:'Reminder: no record today',type:'nightlyNoRecordReminder'}); await createNotificationDoc(...,'nightlyNoRecordReminder'); }
          await setDoc(env, accessToken, 'settings/app', {lastReminderDate: todayStr});
        }
      }
    }
  }
  // Viewer weekly Monday 09:00
  if (cfg.viewerCheckInEnabled===true && addisNow.getDay()===1 && nowMin===9*60) {
    if (cfg.lastViewerCheckInDate !== todayStr) {
      const viewers = await getUsersByRole(env, accessToken, 'viewer');
      for (uid of viewers) { ... type 'viewerWeeklyCheckIn' ... }
      await setDoc(env, accessToken, 'settings/app', {lastViewerCheckInDate: todayStr});
    }
  }
}
```
Deduped by `lastReminderDate` / `lastViewerCheckInDate`, checks `hasTransactionToday` via compositeFilter `createdAt >= startMs && < endMs` (limit 1), Africa/Addis_Ababa window.

### 6. `workers/fcm-relay/wrangler.toml:4-6`
```toml
[triggers]
crons = ["*/30 * * * *"]
```

## TDD Evidence

### RED (before changes)
RelayConfig was `static const String.fromEnvironment` only; `flutter test` would fail for Firestore runtime tests (no `init` method). Worker had no `scheduled` export.

### GREEN

**RelayConfig (FakeFirestore):**
Command: `flutter test test/core/config/relay_config_test.dart -v`
```
00:00 +0: RelayConfig Firestore runtime dart-define fallback when Firestore missing
[RelayConfig] settings/app not found — using env fallback
00:00 +1: RelayConfig Firestore runtime loads relayUrl/relaySecret from Firestore settings/app
[RelayConfig] loaded from Firestore: url=set secret=set
00:00 +6: All tests passed!
```
Tests cover: fallback when missing, load from Firestore, partial override keeps env, empty string does not overwrite, ensureInitialized idempotent, force reload.

**Cron window & hasTransactionToday (Node):**
Command: `node workers/fcm-relay/test/cron_window_test.js`
```
Testing parseTimeToMinutes / isInWindow...
✓ window calc
Testing Addis bounds & hasTransactionToday...
✓ hasTransactionToday bounds
All cron_window tests passed.
```
Cases: `isInWindow('20:00',1200/1230/1260)` true, 1215 false; Addis bounds `2026-08-28 10:00 EAT` → startMs `2026-08-27T21:00Z`, tx inside/outside inclusive start exclusive end.

**Combined gate:**
`flutter analyze --no-pub` — only pre-existing infos (avoid_print, withOpacity, unused_element) — 0 new errors.
`flutter test` — 231 pass, 3 pre-existing failures in `notification_settings_test.dart` (unrelated to this task, also fail on stash@{0} before changes).

### Verify gate
- `dart format lib/core/config/relay_config.dart lib/main.dart lib/core/services/offline_sync_service.dart` — 4 files formatted.
- `npx wrangler deploy` dry-run: not executed (requires secret); `wrangler.toml` syntax validated.

## Env migration answer

**We now use Firestore env, so no `--dart-define` needed.**

- App reads `settings/app { relayUrl, relaySecret }` at startup via `RelayConfig.init()` (called in `main.dart:99` addPostFrameCallback). If the doc is missing or fetch times out, it falls back to the compile-time `String.fromEnvironment('RELAY_URL'/'RELAY_SECRET')` — existing builds with `--dart-define=RELAY_URL=... --dart-define=RELAY_SECRET=...` keep working (backward compat). Empty Firestore strings never clobber a non-empty env.
- Worker still uses `RELAY_SECRET` secret via `wrangler secret put`; app verifies via the same secret fetched from Firestore (store the same value in Firestore).
- Setup: `firebase firestore set settings/app '{relayUrl:"https://cofiz-fcm-relay....workers.dev", relaySecret:"<same as wrangler secret>"}'` — no rebuild needed to rotate.

## Files changed (committed)

- `app/lib/core/config/relay_config.dart` — Firestore runtime + keep dart-define
- `app/lib/core/services/ping_service.dart` — await ensureInitialized
- `app/lib/core/services/offline_sync_service.dart` — await ensureInitialized, updated skip message
- `app/lib/main.dart` — import + init RelayConfig in _initializeNetworkServices
- `workers/fcm-relay/src/index.js` — scheduled handler + helpers (404 guard kept)
- `workers/fcm-relay/wrangler.toml` — triggers crons
- `app/test/core/config/relay_config_test.dart` — 6 tests (fallback, load, partial, idempotent, empty)
- `workers/fcm-relay/test/cron_window_test.js` — window calc + hasTransaction bounds

Commit: `feat(cron+relay): worker scheduled every 30m + Firestore relay env (keep dart-define compat)`
Staged via `git add <above 8 files>` only; local gradle/analysis_options/auth_provider/fcm_service fixes remain unstaged per instructions.
Untracked `app/android/build/` and `workers/fcm-relay/.wrangler/` not committed.

## Self-review findings
- RelayConfig matches `TransactionService` lazy init pattern; `init` timeout 2s avoids blocking startup; `ensureInitialized` called from both services prevents race.
- Cron helpers exported for tests; `getAddisDayBoundsMs` correctly subtracts 3h for EAT (UTC+3 no DST); `hasTransactionToday` uses integerValue range (matches `createdAt` ms).
- Dedupe via `lastReminderDate`/`lastViewerCheckInDate` prevents duplicate nudge within same cron window.
- `dart format` and `flutter analyze` clean for new code; pre-existing 3 notification_settings failures unchanged.
