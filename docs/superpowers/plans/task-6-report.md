# Task 6 Report: Worker `/otp/*` endpoints

## Status

**Complete.** All 12 plan steps executed. `node test/otp/handlers_test.js` exits 0.

## Files created

- `workers/fcm-relay/src/otp/kv.js` — KV code + counter helpers, `randomCode`, `timingSafeEqual`, `sha256Hex`, Telegram chat-id storage
- `workers/fcm-relay/src/otp/telegram.js` — `sendTelegramCode`, `validateTelegramInitData`
- `workers/fcm-relay/src/otp/whatsapp.js` — `sendWhatsAppCode`
- `workers/fcm-relay/src/otp/custom_token.js` — `createCustomToken` (JWT RS256 signed in-worker; carries its own copies of `b64url` / `pemToPkcs8` to avoid touching `src/index.js` exports)
- `workers/fcm-relay/src/otp/handlers.js` — `handleStart`, `handleVerify` (the two route handlers)
- `workers/fcm-relay/src/otp/index.js` — re-export for the router
- `workers/fcm-relay/test/otp/handlers_test.js` — plain Node ESM test, mirrors `test/cron_window_test.js` style

## Files modified

- `workers/fcm-relay/src/index.js` — added the import `import { handleStart as otpStart, handleVerify as otpVerify } from './otp/index.js';` and two branches (`/otp/start`, `/otp/verify`) inside the existing `fetch` handler, placed **after** the `X-Relay-Secret` check and **before** the existing push branch. Existing exports and the `scheduled` handler are untouched. `b64url` / `pemToPkcs8` in `src/index.js` remain private; the OTP module has its own copies.
- `workers/fcm-relay/wrangler.toml` — appended `[[kv_namespaces]]` block with binding `OTP_KV` and id `REPLACE_WITH_REAL_KV_ID` (placeholder, see Concerns). Existing `[triggers]` block preserved. Added comment block listing the three new secrets.

## Diff stat

```
workers/fcm-relay/src/index.js  | +10
workers/fcm-relay/wrangler.toml | +9
+ 7 new files in src/otp/ and test/otp/
```

## Test command + output

```
$ cd workers/fcm-relay && node test/otp/handlers_test.js
Testing randomCode...
✓ randomCode
Testing timingSafeEqual...
✓ timingSafeEqual
Testing E164 regex...
✓ E164
All OTP handler tests passed.
EXIT=0
```

Also re-ran `node test/cron_window_test.js` to confirm no regression: still exits 0.

(Node emits a `MODULE_TYPELESS_PACKAGE_JSON` advisory because the project intentionally has no `package.json`. This is a Node perf hint, not an error; the same advisory appears for `cron_window_test.js` and is pre-existing for the project.)

## Commit

Hash: see final status returned to the dispatcher.

Message: `feat(auth): add worker /otp endpoints with KV and rate limit`

Files committed: only the seven new files under `workers/fcm-relay/src/otp/`, `workers/fcm-relay/test/otp/`, plus the two modifications in `workers/fcm-relay/src/index.js` and `workers/fcm-relay/wrangler.toml`. `app/pubspec.lock` (pre-existing modification from a prior task) was deliberately **not** staged.

## Self-review

| Plan requirement | Verified |
|---|---|
| No new dependencies / no `package.json` created | ✓ (zero `package.json` files added; no `npm install` run) |
| No `firebase-admin` | ✓ (no references in any new file; uses Firestore REST via existing helpers and signs custom tokens with `crypto.subtle`) |
| `node:assert/strict` + plain `node test/...js` | ✓ |
| `b64url` / `pemToPkcs8` duplicated in `src/otp/custom_token.js` (not exported from `src/index.js`) | ✓ |
| `src/index.js` exports unchanged | ✓ (only additive: one import, two route branches) |
| Routes wired after `X-Relay-Secret` check, before push branch | ✓ (see lines 313–319 of updated `src/index.js`) |
| Rate limit (5/hr start, 10/hr verify) via KV counters | ✓ (in `kv.js#bumpCounter`, used in `handlers.js`) |
| 6-digit code, 5-min TTL | ✓ (`CODE_TTL = 300`, `randomCode` returns 6 digits) |
| `REPLACE_WITH_REAL_KV_ID` placeholder in `wrangler.toml` | ✓ |
| Comments in `wrangler.toml` listing new secrets | ✓ |
| No `wrangler` / `npm install` commands run | ✓ |
| Test exits 0 with required `All OTP handler tests passed.` final line | ✓ |

## Concerns

1. **`wrangler.toml` still has `REPLACE_WITH_REAL_KV_ID` placeholder.** The human must run `wrangler kv:namespace create OTP_KV` and patch the id before deploy, as documented in the plan's open-items section. The implementer did **not** run `wrangler` (live auth required).
2. **Three new secrets are required at deploy time** and have **not** been set: `TELEGRAM_BOT_TOKEN`, `WHATSAPP_PHONE_ID`, `WHATSAPP_ACCESS_TOKEN`. Documented in the appended `wrangler.toml` comment block.
3. **Integration path is not unit-tested.** The plan calls for manual on-device QA for the full request/response flow; the Node test only covers pure helpers (randomCode, timingSafeEqual, E164). This matches the existing `test/cron_window_test.js` pattern.
4. **Pre-existing modification to `app/pubspec.lock`** (from a prior task) is uncommitted and was intentionally left alone by this task. It will need to be committed or reverted separately.
5. **Node emits a `MODULE_TYPELESS_PACKAGE_JSON` advisory** for both test files. This is a Node 22+ perf hint that appears for any `*.js` ESM file outside a `package.json` with `"type": "module"`. The project intentionally has no `package.json` in `workers/fcm-relay/`, so the advisory is expected and harmless. Adding `package.json` would violate the "no new dependencies / no package.json" constraint.
