# App-Wide Visual Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved app-wide Cofiz visual cleanup: DM Sans typography, no dot background, no decorative orange card outlines, and direct larger ordinary icons without decorative containers.

**Architecture:** Keep the existing Flutter/Provider architecture and make shared changes first in `AppTheme` and `BackgroundPattern`. Then update the reusable presentation widgets and the explicit screen-level decorative wrappers identified by static search. Preserve semantic containers, functional borders, touch targets, and all business logic.

**Tech Stack:** Flutter 3.41.5, Dart 3.11.3, Material 3, `google_fonts`, Provider, Firebase.

## Global Constraints

- Apply the changes across the entire Flutter app, with the admin dashboard as the first validation surface.
- Replace the current Outfit text theme with DM Sans using the existing `google_fonts` dependency.
- Remove the decorative dot pattern rendered by `BackgroundPattern`.
- Remove decorative orange borders created with `AppColors.primary` around cards and summary panels.
- Remove decorative translucent or opaque containers placed behind ordinary icons across screens and reusable widgets.
- Increase ordinary icon sizes modestly where the existing wrapper removal would make them visually undersized, generally from 20 to 24 and from 24 to 28.
- Preserve `IconButton` touch targets and padding even when its visual background is removed.
- Preserve avatars, badges, status indicators, functional form/input borders, and other semantic containers.
- Do not change business logic, provider behavior, Firebase access, navigation, localization content, or role restrictions.
- Keep the orange accent available for primary actions and semantic emphasis.

---

### Task 1: Update Shared Theme And Background

**Files:**
- Modify: `app/lib/core/theme/app_theme.dart:30-50`
- Modify: `app/lib/presentation/widgets/background_pattern.dart:4-34`

**Interfaces:**
- Preserve `AppTheme.lightTheme`, `AppTheme.darkTheme`, and `BackgroundPattern` constructors.
- `BackgroundPattern` must remain usable wherever existing screens instantiate it.

- [ ] **Step 1: Confirm the current baseline**

Run:

```powershell
flutter analyze
```

Expected: no analyzer errors; existing warnings/info may remain.

- [ ] **Step 2: Change the global text theme to DM Sans**

In both theme getters, replace:

```dart
GoogleFonts.outfitTextTheme()
```

with:

```dart
GoogleFonts.dmSansTextTheme()
```

Keep the existing `.apply(...)` colors and all other theme values unchanged.

- [ ] **Step 3: Disable dot painting without changing layout APIs**

Keep `BackgroundPattern` as a widget with the same constructor and child behavior, but return the child directly when supplied and an empty transparent widget when no child is supplied. The implementation must not instantiate `DotPatternPainter` or paint dots.

Use:

```dart
@override
Widget build(BuildContext context) {
  return child ?? const SizedBox.expand();
}
```

Leave `DotPatternPainter` in place only if removing it would create unrelated churn; it must no longer be used by `BackgroundPattern`.

- [ ] **Step 4: Verify the shared changes**

Run:

```powershell
flutter analyze
```

Expected: no new analyzer errors.

- [ ] **Step 5: Commit the shared cleanup**

```powershell
git add app/lib/core/theme/app_theme.dart app/lib/presentation/widgets/background_pattern.dart
git commit -m "style: refresh global typography and background"
```

### Task 2: Normalize Shared Cards And Icon Widgets

**Files:**
- Modify: `app/lib/presentation/widgets/stats_card.dart:24-75`
- Modify: `app/lib/presentation/widgets/worker_item.dart:24-60`
- Modify: `app/lib/presentation/widgets/worker_transactions_list.dart:120-140`
- Modify: `app/lib/presentation/screens/worker/widgets/worker_action_button.dart:20-40`
- Modify: `app/lib/presentation/screens/worker/widgets/worker_stat_card.dart:20-50`
- Modify: `app/lib/presentation/screens/worker/widgets/worker_transaction_tile.dart:44-76`

**Interfaces:**
- Preserve all widget constructors and callback behavior.
- Preserve avatars, status indicators, notification badges, and semantic colored states.

- [ ] **Step 1: Remove shared decorative orange borders**

In `StatsCard` and `WorkerItem`, remove only the `border: Border.all(...)` entries using `AppColors.primary.withOpacity(0.5)`. Keep each card’s surface, radius, and shadow.

- [ ] **Step 2: Remove ordinary icon background containers**

For ordinary metric/action icons, replace wrapper containers such as:

```dart
Container(
  padding: const EdgeInsets.all(8),
  decoration: BoxDecoration(
    color: cardColor.withOpacity(0.1),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Icon(icon, color: cardColor, size: 20),
)
```

with the direct icon:

```dart
Icon(icon, color: cardColor, size: 24)
```

Use size `24` for ordinary icons currently at `20`, and `28` only where the icon is a prominent action or heading icon currently at `24`.

- [ ] **Step 3: Preserve interaction geometry**

When an icon is inside an `IconButton`, retain the `IconButton` and its padding/tap target. Remove only its decorative `Container` background or set the visual button background to transparent.

- [ ] **Step 4: Verify the shared widgets**

Run:

```powershell
flutter analyze
```

Expected: no new analyzer errors.

- [ ] **Step 5: Commit shared widget cleanup**

```powershell
git add app/lib/presentation/widgets app/lib/presentation/screens/worker/widgets
git commit -m "style: simplify shared cards and icons"
```

### Task 3: Clean Dashboard And Screen-Level Decorative Wrappers

**Files:**
- Modify: `app/lib/presentation/screens/dashboard/dashboard_screen.dart:96-555`
- Modify: `app/lib/presentation/screens/worker/worker_dashboard_screen.dart:150-200`
- Modify: `app/lib/presentation/screens/settings/about_screen.dart:160-190`
- Modify: `app/lib/presentation/screens/settings/settings_screen.dart:295-320`
- Modify: `app/lib/presentation/screens/settings/data_management_screen.dart:180-210`
- Modify: `app/lib/presentation/screens/settings/area_management_screen.dart:235-255`
- Modify: `app/lib/presentation/screens/notifications/notifications_screen.dart:30-55,160-185`
- Modify: `app/lib/presentation/screens/audit/audit_log_screen.dart:260-285`
- Modify: `app/lib/presentation/screens/reports/reports_screen.dart:535-555,675-705`
- Modify: `app/lib/presentation/screens/worker/dialogs/record_purchase_dialog.dart:105-130,360-395`
- Modify: `app/lib/presentation/screens/worker/dialogs/record_return_dialog.dart:60-85,140-160`
- Modify: `app/lib/presentation/screens/transaction/transaction_dialog.dart:380-445`

**Interfaces:**
- Preserve all navigation callbacks, dialog actions, form validation, and provider calls.
- Preserve header backgrounds, avatars, badges, status chips, and semantic warning/info containers.

- [ ] **Step 1: Remove explicit orange borders from dashboard surfaces**

In `dashboard_screen.dart`, remove the two decorative `Border.all(color: AppColors.primary.withOpacity(0.5))` entries found in the compact stats panel and the activity/worker panel. Do not remove borders from date/filter controls if they are functional controls.

- [ ] **Step 2: Remove dashboard icon wrappers**

Update the campaign and notification controls so their existing tap targets remain, but the translucent circular `Container` backgrounds are removed. Increase the notification icon from `24` to `28` only if it remains visually balanced without the wrapper. Remove the metric icon wrapper around the “Today’s Overview” heading and use a direct `Icon` at `24`.

- [ ] **Step 3: Sweep screen-level ordinary icon wrappers**

For each listed screen, remove only containers whose sole purpose is translucent/opaque icon decoration. Keep containers that contain text, a form control, a status state, a badge, or a selected/active state. Convert the child to a direct `Icon` and increase its size from `20` to `24` when appropriate.

- [ ] **Step 4: Remove remaining decorative orange card outlines**

Use the prior search pattern to confirm no decorative card outline remains:

```text
AppColors.primary.withOpacity(0.5)
```

Any remaining match must be reviewed individually. Keep matches that are functional control borders or selection states; remove matches that outline ordinary cards/panels.

- [ ] **Step 5: Verify the screen-level cleanup**

Run:

```powershell
flutter analyze
```

Expected: no new analyzer errors.

- [ ] **Step 6: Commit screen-level cleanup**

```powershell
git add app/lib/presentation/screens
git commit -m "style: remove decorative dashboard wrappers"
```

### Task 4: Build And Device Verification

**Files:**
- No source changes expected.
- Inspect: `app/android/gradle.properties` if the existing low-memory Gradle settings are needed for this machine.

- [ ] **Step 1: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: `0` analyzer errors.

- [ ] **Step 2: Build the debug APK**

Run:

```powershell
flutter build apk --debug
```

Expected: `Built build\app\outputs\flutter-apk\app-debug.apk`.

- [ ] **Step 3: Confirm wireless ADB connectivity**

Run:

```powershell
adb devices -l
```

Expected: device `23046PNC9C` appears with state `device` when the phone is connected.

- [ ] **Step 4: Launch on the phone**

Run:

```powershell
flutter run -d adb-HU4LEMAI7PD64T59-7noFKD._adb-tls-connect._tcp --no-resident
```

Expected: the APK installs and the app launches without a Dart compilation error.

- [ ] **Step 5: Perform manual acceptance checks**

Inspect the admin dashboard, worker dashboard, worker list, settings, notifications, reports, and login screens. Confirm:

- No dot pattern is visible behind content.
- Ordinary cards have no warm-orange outline.
- Ordinary icons render directly without decorative backgrounds.
- Icons remain visually legible and tappable.
- Header, status, notification, avatar, and form affordances still look intentional.
- DM Sans is visible in headings, labels, and body copy.
