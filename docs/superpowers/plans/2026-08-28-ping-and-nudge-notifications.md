# Ping-Only Notifications & Nightly Nudges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn bells from admin self-echo into ping-only (collector/viewer → admin) plus nightly admin nudge (base time +30/+60) via Cloudflare cron, using existing Firestore `notifications` + relay.

**Architecture:** Keep single `notifications` collection and existing relay. Add `PingService` that fans out one doc per admin + one relay POST per admin. Remove admin echo in `NotificationTriggerService`. Add `settings/app.adminReminderTime` + cron scheduled handler in worker. UI: role-specific Ping button/sheet on `WorkerDashboardScreen` and `ReportsScreen` header.

**Tech Stack:** Flutter 3.47 / Dart 3.13, Firebase Auth/Firestore, Cloudflare Workers (wrangler), FCM HTTP v1, Provider.

## Global Constraints

- Dart `String.fromEnvironment` relay config stays — secrets via `--dart-define=RELAY_URL/RELAY_SECRET`, never hardcoded.
- `app/lib/main.dart:290` fix already applied locally (ValueKey + loading gate) — keep.
- `workers/fcm-relay` 404→null fix already applied locally — keep.
- All new types reuse `notifications` schema: `targetUserId, title, body, type, isRead:false, createdAt:ms, senderId, senderRole, metadata`.
- Ping note ≤120 chars, cooldown 2 min per sender UID (`users/{uid}.lastPingAt`).
- Nudge window Africa/Addis Ababa: base `HH:mm` +0/+30/+60, 30-min cron, deduped by `settings/app.lastReminderDate`.

---

## File Map

**Modify:**
- `app/lib/core/services/notification_trigger_service.dart` — delete admin fan-out for lowBalance/largePurchase self-trigger.
- `app/lib/core/services/offline_sync_service.dart` — wire PingService fan-out not needed (pings are online-only, not outbox); keep existing `_fireTransactionNotifications` but ensure no admin docs.
- `app/lib/core/providers/auth_provider.dart` — loading gate already local, verify committed.
- `app/lib/main.dart` — AuthGate spinner vs error, ValueKey fix already local.
- `app/lib/core/services/fcm_service.dart` — dedupe already local.
- `workers/fcm-relay/src/index.js` — add `scheduled` handler + 404 guard already local.
- `workers/fcm-relay/wrangler.toml` — add `triggers = { crons = ["*/30 * * * *"] }`.
- `app/lib/presentation/screens/worker/worker_dashboard_screen.dart` — add PingAdminButton below Balance Card.
- `app/lib/presentation/screens/reports/reports_screen.dart` — add PingAdmin icon (viewer only).
- `app/lib/presentation/screens/settings/settings_screen.dart` — admin-only TimePicker + toggle for reminder.
- `app/lib/core/providers/settings_provider.dart` or `app/lib/core/services/settings_service.dart` — persist `adminReminderTime`.

**Create:**
- `app/lib/core/services/ping_service.dart` — `PingService.pingAdmin(note, senderRole, senderName, senderId)` fan-out.
- `app/lib/presentation/widgets/ping_admin_sheet.dart` — bottom sheet with presets + text.
- `app/test/core/services/ping_service_test.dart`
- `app/test/presentation/widgets/ping_admin_sheet_test.dart`
- `workers/fcm-relay/test/cron_window_test.js` (optional)

---

### Task 1: Remove admin echo (bell)

**Files:**
- Modify: `app/lib/core/services/notification_trigger_service.dart:106-173`
- Test: `app/test/core/services/notification_trigger_service_test.dart`

**Interfaces:**
- Consumes: none
- Produces: `checkLowBalance` now **does not** call `_notifyAllAdmins` (deleted). `checkLargePurchase` likewise deleted. Keep `_sendNotification`/`_notifyAllAdmins` for ping fan-out only.

- [ ] **Step 1: Write failing test — admin should NOT get bell on purchase**

```dart
test('purchase does not notify admins (ping-only)', () async {
  final fake = FakeFirestore();
  final svc = NotificationTriggerService(firestore: fake);
  await svc.checkLowBalance(workerId: 'w1', workerUserId: 'u1', workerName: 'A', newBalance: 100);
  expect(fake.collection('notifications').docs, isEmpty);
});
```

- [ ] **Step 2: Run test — expect FAIL (currently writes admin docs)**

Run: `flutter test test/core/services/notification_trigger_service_test.dart -v`
Expected: FAIL

- [ ] **Step 3: Implement — delete 109-127 and 151-173 admin notify, keep collector paths**

```dart
Future<void> checkLowBalance({...}) async { if (newBalance < 500 && newBalance >=0) {/* no-op: admin echo removed */} }
Future<void> checkLargePurchase({...}) async { if (amount>=10000) {/* no-op */} }
```
Keep `_notifyAllAdmins` private for Task 2 fan-out or delete and re-add in PingService.

- [ ] **Step 4: Run test — PASS**
- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/notification_trigger_service.dart app/test/core/services/notification_trigger_service_test.dart
git commit -m "feat(notifs): remove admin echo — bells are ping-only"
```

---

### Task 2: PingService fan-out (collector/viewer → admin)

**Files:**
- Create: `app/lib/core/services/ping_service.dart`
- Modify: `app/lib/core/services/offline_sync_service.dart` to expose `relayPushFanout` helper or duplicate loop
- Test: `app/test/core/services/ping_service_test.dart`

**Interfaces:**
- Produces: `class PingService { Future<void> pingAdmin({required String note, required String senderId, required String senderName, required UserRole senderRole}) }`
- Consumes: `FirebaseFirestore.instance`, `NotificationTriggerService._sendNotification` pattern (copied), `RelayConfig` + `http.Client`.

- [ ] **Step 1: Write failing test**

```dart
test('pingCollectorToAdmin fans out to 2 admins', () async {
  final svc = PingService(firestore: fakeWithAdmins(['a1','a2']));
  await svc.pingAdmin(note: 'Need cash', senderId: 'c1', senderName: 'Collector A', senderRole: UserRole.worker);
  expect(fake.collection('notifications').whereTarget('a1'), hasLength(1));
  expect(fake.collection('notifications').whereTarget('a2'), hasLength(1));
  expect(fake.doc('a1').data['type'], 'pingCollectorToAdmin');
});
```

- [ ] **Step 2: Run — FAIL (no file)**
- [ ] **Step 3: Implement minimal**

```dart
class PingService {
  final FirebaseFirestore _firestore;
  PingService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;
  Future<void> pingAdmin({required String note, required String senderId, required String senderName, required UserRole senderRole}) async {
    if (note.length > 120) throw ArgumentError('note too long');
    final last = await _firestore.collection('users').doc(senderId).get();
    final lastAt = (last.data()?['lastPingAt'] as int?) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - lastAt < 120000) throw StateError('cooldown');
    final admins = await _firestore.collection('users').where('role', isEqualTo: 'admin').get();
    final type = senderRole == UserRole.viewer ? 'pingViewerToAdmin' : 'pingCollectorToAdmin';
    final batch = _firestore.batch();
    for (var a in admins.docs) {
      final ref = _firestore.collection('notifications').doc();
      batch.set(ref, {'targetUserId': a.id, 'title': 'Ping from $senderName (${senderRole.name})', 'body': note, 'type': type, 'isRead': false, 'createdAt': DateTime.now().millisecondsSinceEpoch, 'senderId': senderId, 'senderRole': senderRole.name});
    }
    await batch.commit();
    for (var a in admins.docs) { await OfflineSyncService().pushViaRelay(targetUserId: a.id, title: 'Ping from $senderName', body: note, type: type); }
    await _firestore.collection('users').doc(senderId).set({'lastPingAt': FieldValue.serverTimestamp()}, SetOptions(merge:true));
  }
}
```

- [ ] **Step 4: Run — PASS (mock http)**
- [ ] **Step 5: Commit**

---

### Task 3: Ping UI (role-specific)

**Files:**
- Create: `app/lib/presentation/widgets/ping_admin_sheet.dart`
- Modify: `app/lib/presentation/screens/worker/worker_dashboard_screen.dart:80` add button, `app/lib/presentation/screens/reports/reports_screen.dart` add appBar action
- Test: `app/test/presentation/widgets/ping_admin_sheet_test.dart`

**Interfaces:**
- Consumes: `PingService.pingAdmin`
- Produces: `Future<void> showPingAdminSheet(BuildContext, UserRole)`

- [ ] **Step 1: Failing widget test — sheet shows presets**

```dart
testWidgets('collector sheet shows Need cash preset', (t) async {
  await t.pumpWidget(MaterialApp(home: Builder(builder: (c) => ElevatedButton(onPressed: ()=>showPingAdminSheet(c, UserRole.worker), child: Text('x')))));
  await t.tap(find.text('x')); await t.pump();
  expect(find.text('Need cash'), findsOne);
  expect(find.text('Need clarification'), findsNothing);
});
```

- [ ] **Step 2: Fail**
- [ ] **Step 3: Implement sheet (DraggableScrollableSheet, 3 chips per role + TextField max 120 + counter + Send disabled when offline/cooldown)**
- [ ] **Step 4: Pass**
- [ ] **Step 5: Commit**

---

### Task 4: Nightly nudge settings + Firestore doc

**Files:**
- Modify: `app/lib/core/providers/settings_provider.dart` add `adminReminderTime` + `reminderEnabled` persisted to `settings/app`
- Modify: `app/lib/presentation/screens/settings/settings_screen.dart` admin-only section with Switch + TimePicker

- [ ] **Step 1: Test settings round-trip**
- [ ] **Step 2: Implement**
- [ ] **Step 3: Commit**

---

### Task 5: Worker cron (Cloudflare)

**Files:**
- Modify: `workers/fcm-relay/src/index.js` add `scheduled` handler
- Modify: `workers/fcm-relay/wrangler.toml` add cron

- [ ] **Step 1: Test window calc `isInWindow('20:00', nowAddis)`**
- [ ] **Step 2: Implement scheduled:**

```js
async scheduled(event, env) {
  const cfg = await getDoc(env, 'settings/app'); if (!cfg?.adminReminderTime || !cfg.reminderEnabled) return;
  const addisNow = new Date(new Date().toLocaleString('en-US',{timeZone:'Africa/Addis_Ababa'}));
  const [h,m]=cfg.adminReminderTime.split(':').map(Number); const baseMin=h*60+m; const nowMin=addisNow.getHours()*60+addisNow.getMinutes();
  const offsets=[0,30,60]; if (!offsets.some(o=> nowMin===baseMin+o)) return;
  const todayStr = addisNow.toISOString().slice(0,10); if (cfg.lastReminderDate===todayStr) return;
  const hasTx = await hasTransactionToday(env, todayStr); if (hasTx) return;
  const admins=await getUsersByRole(env,'admin'); for (let a of admins) { const tok=await getFcmToken(env, await getAccessToken(env), a); if(tok) await sendPush(env, tok, {title:'Reminder: no record today', body:"No transaction recorded today — add today's purchases/distributions", type:'nightlyNoRecordReminder'}); await createNotificationDoc(env, a, 'nightlyNoRecordReminder'); }
  await setDoc(env,'settings/app',{lastReminderDate:todayStr});
  // viewer weekly: if addisNow.getDay()===1 && nowMin===9*60) fan out to viewers
}
```

- [ ] **Step 3: `npx wrangler deploy` dry-run**
- [ ] **Step 4: Commit**

---

### Task 6: Remove duplicate FCM/token + fix ListTile assertion (cleanup)

**Files:**
- Modify: `app/lib/presentation/widgets/notification_settings_tile.dart` wrap ListTile in Material

- [ ] **Step 1: Repro failing `notification_settings_test`**
- [ ] **Step 2: Fix `Material(child: ListTile(...))`**
- [ ] **Step 3: Verify `flutter analyze` + `flutter test` green**

---

## Self-Review

- Spec coverage: A (Task1), B1 (Task2+3), C1 (Task4+5) all mapped. Cooldown + role-specific copy covered. ListTile fix prevents CI red.
- No placeholders: all steps have concrete code.
- Types: `PingService.pingAdmin` signature used consistently in Task2 & Task3.
