# Feature: Ethiopian Calendar Support

**Date:** 2026-08-29
**Status:** Approved design — ready to plan
**Target codebase:** `app/` (Cofiz Flutter app)
**Co-dependency:** none

## Goal

Add an optional Ethiopian-calendar display and input mode, controlled by a setting under the existing **Language** section. All dates are stored in Firestore as `Timestamp` / `millisecondsSinceEpoch` (Gregorian); only the **presentation** and **date picker** change.

## Out of scope (v1)

- Fiscal year handling tied to Ethiopian calendar.
- Ethiopian holiday list.
- Per-record date format override (the setting is global).
- Ethiopian calendar in receipts PDFs beyond a localized date string in the header.

## User-visible behavior

### Settings → Language → Calendar

A new sub-section under the existing language picker with a segmented control: `Gregorian | Ethiopian`.

- Default: follows the language — Amharic → Ethiopian, English → Gregorian.
- Persisted in `shared_preferences` under key `calendar_type_v1` (`"gregorian"` or `"ethiopian"`).

### Display

Anywhere a date is currently rendered (transaction lists, expense/income lists, audit log, reports, charts, receipts, the collector detail header), the format changes based on the setting:

- Gregorian example (en): `Nov 12, 2026`.
- Ethiopian example (am): `12 ህዳር 2018`.
- Gregorian example (am, when forced): `12/11/2018` (Gregorian).
- Ethiopian example (en, when forced): `12 Hidar 2018`.

We do **not** localize the Ethiopian month names differently per app language — Ethiopian names are always in Amharic script; Gregorian names follow the app language.

### Input

- Date pickers used when recording transactions, income, expenses, and debts display Ethiopian year/month/day inputs when the setting is Ethiopian.
- Picking `15 ህዳር 2018` is converted to Gregorian before saving.
- Time pickers (where they exist) are unaffected.

### Reports

- `fl_chart` x-axis labels follow the selected calendar.
- "Today", "This week", "This month" boundaries:
  - In Ethiopian mode, the week starts on **Saturday** (Ethiopian week start), the month follows Ethiopian months.
  - "This month" labels are `ህዳር 2018` vs `November 2026`.

## Architecture

### 1. `lib/core/utils/ethiopian_calendar.dart` (new)

Thin wrapper over the `ethio_calendar` pub package:

- `EthDate gregorianToEthiopian(DateTime d)` — returns a small value type `EthDate(year, month, day)`.
- `DateTime ethiopianToGregorian(int year, int month, int day)`.
- `String formatEthDate(EthDate d, {String languageCode})` — for the formatted output.

### 2. `lib/core/utils/date_formatter.dart` (new)

A single `DateFormatter` facade that all UI code uses:

```dart
class DateFormatter {
  static String formatDate(DateTime d, {String? languageCode});
  static String formatDateTime(DateTime d, {String? languageCode});
  static String formatRelative(DateTime d, {String? languageCode}); // "Today", "Yesterday", etc.
  static String formatMonthYear(DateTime d, {String? languageCode});
  static DateTime parseUserInput(int year, int month, int day, {required CalendarType calendar});
  static EthDate toEthiopian(DateTime d);
}
```

The formatter reads the current `CalendarType` from a `SettingsProvider` (inherited via `Provider.of(context)` or a static accessor set at app start).

### 3. `lib/core/providers/settings_provider.dart` — extend

Add `CalendarType calendarType` (enum: `gregorian`, `ethiopian`) with `setCalendarType(...)` and persistence in `shared_preferences`.

### 4. `pubspec.yaml` — add dependency

```yaml
ethio_calendar: ^1.0.0
```

(Use whatever the latest version on pub.dev is at implementation time; the API is small and stable.)

### 5. Localization

Add to `app_localizations_en.dart` and `app_localizations_am.dart`:
- `calendarType` → "Calendar"
- `gregorian` → "Gregorian" / "ግሪጎሪያን"
- `ethiopian` → "Ethiopian" / "ኢትዮጵያዊ"
- The 13 Ethiopian month names: `መስከረም, ጥቅምት, ኅዳር, ታኅሣሥ, ጥር, የካቲት, መጋቢት, ሚያዝያ, ግንቦት, ሰኔ, ሐምሌ, ነሐሴ, ጳጉሜ`.

### 6. Settings page

- `lib/presentation/screens/settings/settings_screen.dart` — under the existing language section, add the new "Calendar" sub-section.
- `lib/presentation/screens/settings/pin_lock_settings_screen.dart` already exists (feature #2) — leave that as a sibling.

### 7. UI migration

- Replace every `DateFormat.yMMMd().format(d)` and equivalent across `lib/presentation/` with `DateFormatter.formatDate(d)`.
- Replace every `showDatePicker` usage with a wrapper that shows Ethiopian inputs when the setting is on. Easiest: build a custom `EthDatePickerDialog` modeled on Material's date picker, using three `DropdownButton` widgets for year / month / day. Day options depend on the selected month/year.
- Update `fl_chart` x-axis formatters in `reports_screen.dart` to use `DateFormatter.formatMonthYear`.

### 8. Edge cases

- Ethiopian year has 13 months; the 13th (`ጳጉሜ`) has 5 or 6 days. The picker must allow pagume entries.
- Ethiopian leap year logic: a year is a leap year if `year % 4 == 3`. `ethio_calendar` handles this.
- Conversion must be UTC-safe. Firestore `Timestamp.toDate()` returns local time. We treat the user's local timezone as authoritative (consistent with existing app behavior — no timezones are stored).
- Day-of-week: Saturday = 7 in Ethiopian convention, but we keep our internal 1..7 = Mon..Sun and just relabel the week start for "this week" boundaries.

## Data model

No Firestore schema changes. All storage remains Gregorian `Timestamp` / `millisecondsSinceEpoch`.

| Storage | Key | Value |
|---|---|---|
| `shared_preferences` | `calendar_type_v1` | `"gregorian"` (default English) or `"ethiopian"` (default Amharic) |

## Security considerations

- This feature reads no PII beyond what's already shown. No security review needed beyond the standard change.
- Date pickers must validate user input (e.g., 30 in ጳጉሜ is invalid; the picker disables invalid days).

## Error handling

| Failure | UX |
|---|---|
| Conversion throws (out-of-range) | Fall back to Gregorian display with a "—" suffix |
| Date picker receives invalid selection | Disable OK button |
| `ethio_calendar` package throws on edge cases | Caught, fallback as above |

## Testing

- **Unit:** `EthiopianCalendar` round-trips (Gregorian → Ethiopian → Gregorian); `DateFormatter` outputs in en + am.
- **Widget:** `EthDatePickerDialog` golden tests, `settings_screen` with calendar section.
- **Integration:** `SettingsProvider.setCalendarType` persists; UI re-renders on change.
- **Manual:** Setting to Ethiopian in EN mode, Am mode, and back. Date pickers across all dialogs. Reports chart axis labels. Receipt header.

## Open items (deferred)

1. **Calendar in Amharic locale only by default.** Some users may want Ethiopian dates in English UI text — supported by the setting being independent of language.
2. **Per-user vs per-device.** The setting is per-device (`shared_preferences`). If a user signs in on a new device, the calendar type follows the device. To be revisited.
3. **Receipt PDF formatting.** The receipt PDF generator (`lib/core/services/...` for receipts) needs to use `DateFormatter` too — added to the migration list.
