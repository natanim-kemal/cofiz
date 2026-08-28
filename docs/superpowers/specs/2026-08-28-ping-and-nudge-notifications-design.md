# Ping-Only Notifications & Nightly Nudges — Design Spec

**Date:** 2026-08-28
**Status:** Draft → Awaiting user sign-off before plan
**Scope:** A + B1 + C1 (remove admin echo, collector/viewer ping admin, nightly reminder via Cloudflare cron)

## 1. Goals & Non-Goals

**Goals**
- Admin no longer gets a bell for actions he himself records (distributions, purchases). Bells become pings only.
- Collectors and viewers can ping admins with an optional short note (≤120 chars), with role-specific copy and placement, using the existing bell + FCM push pipeline.
- Nightly nudge: admin picks one base time (e.g., 20:00 Addis). If zero transactions recorded for that calendar day, send reminder at +0 / +30 / +60 min to each admin (push + bell). Second nudge: weekly viewer check-in (Monday 09:00).

**Non-Goals (v1)**
- No threaded replies / chat.
- No WorkManager / client-side alarms.
- No new FCM topics or email digests beyond existing `_maybeQueueEmail` gate.

## 2. Architecture

- **Flutter app:** `NotificationTriggerService` stripped of admin echo for `lowBalance`/`largePurchase` distribution/purchase paths. New `PingService` reuses `NotificationTriggerService._sendNotification` + `OfflineSyncService._pushViaRelay` fan-out (one notification doc per admin UID, one relay POST per admin token). UI components: `PingAdminSheet` (bottom sheet with 3 presets + free text + counter + send + cooldown hint) and `PingAdminButton` placed on `WorkerDashboardScreen` (collector) and `ReportsScreen` header (viewer, visible only when `isViewer`).
- **Firestore:** Reuse `notifications` collection. Document shape: `{targetUserId, title, body, type, isRead:false, createdAt:ms, senderId, senderRole, metadata:{note, preset}}`. New setting doc: `settings/app { adminReminderTime:"HH:mm", reminderEnabled:bool, viewerCheckInEnabled:bool }` (Addis timezone stored as HH:mm, interpreted as Africa/Addis Ababa).
- **Cloudflare Worker relay:** Existing `index.js` single-target push stays. App fans out by looping admin UIDs (simple, no new endpoint). Worker adds `scheduled` handler (cron `*/30 * * * *`) for nightly nudges; reads `settings/app` and today's transaction count, then pushes to admins/viewers. Keeps existing `getFcmToken` 404→null fix and stale-token cleanup.

## 3. Data Model

**NotificationType (extend):**
```
pingCollectorToAdmin, pingViewerToAdmin, nightlyNoRecordReminder, viewerWeeklyCheckIn
```
(Keep existing: moneyDistributed, commissionEarned, lowBalance, purchaseRecorded — but lowBalance/purchaseRecorded will no longer fan out to admins for self-triggered actions.)

**Settings doc `settings/app`:**
```
adminReminderTime: string "20:00"  // HH:mm, Africa/Addis Ababa
reminderEnabled: bool
viewerCheckInEnabled: bool
```

**Per-user ping throttle:** `users/{uid} { lastPingAt: serverTimestamp }` updated on successful ping; Cloud Firestore rule + client check enforce 2-min cooldown.

## 4. Flows

### 4.1 Ping collector/viewer → admin
1. User taps Ping Admin (online-only; button disabled + toast when `connectivity==none`).
2. Sheet: role-specific presets — collector: ["Need cash", "Issue with record", "Report ready"]; viewer: ["Need clarification", "Report looks off", "Request summary"]; plus free text ≤120.
3. `PingService.pingAdmin(note)`:
   - Validate note, check cooldown (`now - lastPingAt < 2m` → snack + return).
   - Query `users where role==admin` (cache + server, 3s timeout, fallback to cached admin UID set).
   - Batch write `notifications` docs (one per admin) with `type` per sender role.
   - For each admin: `_pushViaRelay(targetUserId:adminUid, title:"Ping from {senderName} ({role})", body:note, type:ping...)` (bell-only if token missing).
   - Update `users/{senderUid}.lastPingAt`.
4. Admin sees bell badge + (if background) high-priority FCM via `cofiz_main_channel`.

### 4.2 Distribution / purchase (after admin echo removal)
- `OfflineSyncService._fireTransactionNotifications`: on `distribution` → `notifyMoneyDistributed` + relay to collector only. On `purchase` → `notifyCommissionEarned` + relay to collector if `commission>0`; relay-only to collector for lowBalance/largePurchase thresholds. No `notifications` docs for admins from these triggers.

### 4.3 Nightly nudge (admin)
- Worker cron `scheduled` every 30 min reads `settings/app`. If `reminderEnabled` and `now` in `[base, base+60]` at 0/30/60 offsets, query `transactions` where `date == todayString` (Addis day, `yyyy-MM-dd`). If count==0 and not already sent for today (track `settings/app.lastReminderDate`), fan-out push+bell to admins: title `Reminder: no record today`, body `No transaction recorded today — add today's purchases/distributions`. Mark `lastReminderDate`.

### 4.4 Viewer weekly check-in
- Cron Monday 09:00 Addis: query `users where role==viewer`; for each, write `viewerWeeklyCheckIn` bell + relay push `Check in: see this week's business`.

## 5. Security, Limits, Errors

- **Rules:** `notifications` allow `create` if `request.auth != null && request.resource.data.senderId == request.auth.uid && request.resource.data.body.size() <= 120`; admins `allow read where resource.data.targetUserId == request.auth.uid`; throttle: `allow create if !exists(/users/$(auth.uid)) || request.time > get(/users/$(auth.uid)).data.lastPingAt + duration.value(2, 'm')`.
- **Token handling:** Relay `getFcmToken` returns null on 404 (already fixed); sendPush logs body on failure, cleans stale tokens, returns `sent:false` → app still has bell.
- **Offline:** Pings are online-only (explicit). Distribution/purchase pings remain outbox-queued and fire at sender sync time (existing semantics, user-confirmed).
- **No admins found:** No-op.

## 6. UI

- **Collector** (`WorkerDashboardScreen`): `Ping Admin` outlined button below Balance Card, icon `campaign`, subtitle `Admin will be notified`. Sheet title `Ping admin`.
- **Viewer** (`ReportsScreen` app bar action): `Ping Admin` icon button, sheet title `Ping admin — Reports` with viewer presets.
- **Settings** (`SettingsScreen`, admin-only section): Toggle `Nightly reminder` + `TimePicker` for `adminReminderTime` + helper text `Checks at +0/+30/+60 min`.

## 7. Testing

- **Unit:** `PingService` cooldown, note validation, cron window calc (base 20:00 → 20:00/20:30/21:00), today transaction count query.
- **Widget:** `PingAdminSheet` renders presets + counter, disables send when offline or cooldown, `WorkerDashboardScreen` shows button only for collectors, `ReportsScreen` only for viewers.
- **Integration/manual:** Collector ping → admin bell+push <3s; viewer ping → admin; nightly cron dry-run with zero transactions; verify no admin bell on distribution/purchase after removal.
- **Existing suite:** `flutter analyze --no-pub` + `flutter test` (fix pre-existing `notification_settings_test` ListTile/Material wrapper if needed).

## 8. Future Nudge Ideas (bucket, not v1)

- `lowStockAlert`, `dailySummary` (21:00 digest), `goalAchieved`, `inactivityPing` (collector 3 days no purchase), `viewerInsight` (viewer 7 days no report open).

## 9. Rollout

- Phase 1: Land A (remove admin echo) + B1 (ping).
- Phase 2: Deploy worker cron + settings UI (C1).
- Pings go via existing relay (no secrets in code, `--dart-define` relay config stays).

## 10. Open Questions (resolved)

- Ping note optional with presets: yes, b per role.
- Nightly timing: single base time +30/+60: yes.
- Offline ping queuing: online-only (user confirmed send-at-sync semantics for normal transactions, but pings should be explicit online action).
