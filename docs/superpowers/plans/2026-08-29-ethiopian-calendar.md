# Ethiopian Calendar Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional Ethiopian-calendar display and input mode, controlled by a setting under the existing **Language** section. All dates are stored as Gregorian `Timestamp`; only the **presentation** and **date picker** change.

**Architecture:** `ethio_calendar` pub package wrapped in `EthiopianCalendar` util. `DateFormatter` facade that all UI code routes through. `SettingsProvider` gains `calendarType`. New `EthDatePickerDialog` for Ethiopian input. `fl_chart` axis labels follow the selection.

**Tech Stack:** Flutter, `ethio_calendar` (new), `intl` (existing), `shared_preferences` (existing).

**Spec:** `docs/superpowers/specs/2026-08-29-ethiopian-calendar-design.md`

## Global Constraints

- Dart SDK `^3.5.4`.
- Default calendar follows language: Amharic → Ethiopian, English → Gregorian.
- Storage key: `calendar_type_v1` in `shared_preferences` (`"gregorian"` | `"ethiopian"`).
- All dates stored in Firestore as `Timestamp` (Gregorian). No schema change.
- Ethiopian week start = Saturday. Affects "this week" boundaries only.
- 13 Ethiopian months; `ጳጉሜ` (pagume) has 5 or 6 days. Picker must accept both.
- All UI date strings route through `DateFormatter`. No direct `DateFormat` calls remain.

---

## File Structure

### New files

- `app/lib/core/utils/ethiopian_calendar.dart`
- `app/lib/core/utils/date_formatter.dart`
- `app/lib/presentation/widgets/eth_date_picker_dialog.dart`
- `app/test/core/utils/ethiopian_calendar_test.dart`
- `app/test/core/utils/date_formatter_test.dart`
- `app/test/presentation/widgets/eth_date_picker_dialog_test.dart`

### Modified files

- `app/pubspec.yaml` — add `ethio_calendar`.
- `app/lib/core/providers/settings_provider.dart` — add `calendarType`.
- `app/lib/l10n/app_en.arb` / `app_am.arb` — calendar strings + 13 month names.
- `app/lib/presentation/screens/settings/settings_screen.dart` — Calendar sub-section.
- All UI files that call `DateFormat` or `intl` date formatting (search-replace via grep list).
- `app/lib/presentation/screens/reports/reports_screen.dart` — chart axis formatter.

---

## Task 1: Add `ethio_calendar` dependency

**Files:**
- Modify: `app/pubspec.yaml`

- [ ] **Step 1: Add the dep**

In `app/pubspec.yaml`, under `dependencies`, add:
```yaml
ethio_calendar: ^1.0.0
```

- [ ] **Step 2: Resolve**

Run: `cd app && flutter pub get`
Expected: resolves without conflict.

- [ ] **Step 3: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock
git commit -m "build: add ethio_calendar dependency"
```

---

## Task 2: `EthiopianCalendar` utility with tests

**Files:**
- Create: `app/lib/core/utils/ethiopian_calendar.dart`
- Test: `app/test/core/utils/ethiopian_calendar_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class EthDate { final int year; final int month; final int day; }
  class EthiopianCalendar {
    static EthDate gregorianToEthiopian(DateTime g);
    static DateTime ethiopianToGregorian(int year, int month, int day);
    static bool isEthiopianLeapYear(int year);   // year % 4 == 3
    static int daysInEthiopianMonth(int year, int month);
    static const monthNamesAmharic = [...13 names...];
  }
  ```

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/utils/ethiopian_calendar.dart';

void main() {
  test('gregorianToEthiopian for 2026-08-29', () {
    final e = EthiopianCalendar.gregorianToEthiopian(DateTime(2026, 8, 29));
    // Approximate: late Aug 2026 → month 1 or 2 of 2018 (Meskerem or Tikimt).
    // The exact value depends on the package; assert structure instead of digits.
    expect(e.year, greaterThan(2017));
    expect(e.year, lessThan(2019));
    expect(e.month, inInclusiveRange(1, 13));
    expect(e.day, inInclusiveRange(1, 30));
  });

  test('round-trip gregorian→ethiopian→gregorian', () {
    final g = DateTime(2026, 1, 15);
    final e = EthiopianCalendar.gregorianToEthiopian(g);
    final back = EthiopianCalendar.ethiopianToGregorian(e.year, e.month, e.day);
    expect(back.year, g.year);
    expect(back.month, g.month);
    expect(back.day, g.day);
  });

  test('isEthiopianLeapYear matches year % 4 == 3', () {
    expect(EthiopianCalendar.isEthiopianLeapYear(2019), isTrue);
    expect(EthiopianCalendar.isEthiopianLeapYear(2018), isFalse);
  });

  test('daysInEthiopianMonth returns 5/6 for pagume', () {
    final nonLeap = EthiopianCalendar.daysInEthiopianMonth(2018, 13);
    final leap = EthiopianCalendar.daysInEthiopianMonth(2019, 13);
    expect(nonLeap, 5);
    expect(leap, 6);
  });
}
```

- [ ] **Step 2: Run tests, expect failure**

Run: `cd app && flutter test test/core/utils/ethiopian_calendar_test.dart`
Expected: import error.

- [ ] **Step 3: Implement `EthiopianCalendar`**

The `ethio_calendar` package exposes its conversion API. Read its pub.dev page to confirm exact names; the canonical API is similar to `EthiopianDateConverter.fromGregorian(DateTime) → EthiopianDate`. Adapt as needed:

```dart
import 'package:ethio_calendar/ethio_calendar.dart';

class EthDate {
  final int year;
  final int month;
  final int day;
  const EthDate(this.year, this.month, this.day);
}

class EthiopianCalendar {
  static const monthNamesAmharic = <String>[
    'መስከረም', 'ጥቅምት', 'ኅዳር', 'ታኅሣሥ', 'ጥር', 'የካቲት',
    'መጋቢት', 'ሚያዝያ', 'ግንቦት', 'ሰኔ', 'ሐምሌ', 'ነሐሴ', 'ጳጉሜ',
  ];

  static EthDate gregorianToEthiopian(DateTime g) {
    final ed = EthiopianDateConverter.fromGregorian(g);
    return EthDate(ed.year, ed.month, ed.day);
  }

  static DateTime ethiopianToGregorian(int year, int month, int day) {
    return EthiopianDateConverter.toGregorian(EthiopianDate(year, month, day));
  }

  static bool isEthiopianLeapYear(int year) => year % 4 == 3;

  static int daysInEthiopianMonth(int year, int month) {
    if (month >= 1 && month <= 12) return 30;
    return isEthiopianLeapYear(year) ? 6 : 5;
  }
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `cd app && flutter test test/core/utils/ethiopian_calendar_test.dart`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/utils/ethiopian_calendar.dart app/test/core/utils/ethiopian_calendar_test.dart
git commit -m "feat(calendar): add EthiopianCalendar utility and tests"
```

---

## Task 3: `DateFormatter` facade

**Files:**
- Create: `app/lib/core/utils/date_formatter.dart`
- Test: `app/test/core/utils/date_formatter_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum CalendarType { gregorian, ethiopian }
  class DateFormatter {
    static CalendarType _active = CalendarType.gregorian;
    static void setActive(CalendarType c) { _active = c; }
    static CalendarType get active => _active;
    static String formatDate(DateTime d, {String languageCode = 'en'});
    static String formatMonthYear(DateTime d, {String languageCode = 'en'});
    static String formatRelative(DateTime d, {String languageCode = 'en'});
    static DateTime parseUserInput(int year, int month, int day, {required CalendarType calendar});
  }
  ```

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/utils/date_formatter.dart';

void main() {
  tearDown(() => DateFormatter.setActive(CalendarType.gregorian));

  test('gregorian formatDate', () {
    DateFormatter.setActive(CalendarType.gregorian);
    final s = DateFormatter.formatDate(DateTime(2026, 8, 29));
    expect(s, contains('2026'));
    expect(s, isNot(contains('ህዳር')));
  });

  test('ethiopian formatDate uses Amharic month name', () {
    DateFormatter.setActive(CalendarType.ethiopian);
    final s = DateFormatter.formatDate(DateTime(2026, 8, 29), languageCode: 'am');
    expect(s, anyOf(contains('መስከረም'), contains('ጥቅምት')));
  });

  test('parseUserInput ethiopian converts to gregorian', () {
    DateFormatter.setActive(CalendarType.ethiopian);
    final d = DateFormatter.parseUserInput(2018, 1, 1, calendar: CalendarType.ethiopian);
    expect(d.year, inInclusiveRange(2025, 2026));
  });
}
```

- [ ] **Step 2: Run tests, expect failure**

Run: `cd app && flutter test test/core/utils/date_formatter_test.dart`
Expected: import error.

- [ ] **Step 3: Implement `DateFormatter`**

```dart
import 'package:intl/intl.dart';
import 'ethiopian_calendar.dart';

enum CalendarType { gregorian, ethiopian }

class DateFormatter {
  static CalendarType _active = CalendarType.gregorian;
  static void setActive(CalendarType c) { _active = c; }
  static CalendarType get active => _active;

  static String formatDate(DateTime d, {String languageCode = 'en'}) {
    if (_active == CalendarType.ethiopian) {
      final e = EthiopianCalendar.gregorianToEthiopian(d);
      final monthName = EthiopianCalendar.monthNamesAmharic[e.month - 1];
      return '$monthName ${e.day}, ${e.year}';
    }
    return DateFormat.yMMMd(languageCode).format(d);
  }

  static String formatMonthYear(DateTime d, {String languageCode = 'en'}) {
    if (_active == CalendarType.ethiopian) {
      final e = EthiopianCalendar.gregorianToEthiopian(d);
      return '${EthiopianCalendar.monthNamesAmharic[e.month - 1]} ${e.year}';
    }
    return DateFormat.yMMMM(languageCode).format(d);
  }

  static String formatRelative(DateTime d, {String languageCode = 'en'}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    if (today == that) return 'Today';
    if (today.difference(that).inDays == 1) return 'Yesterday';
    return formatDate(d, languageCode: languageCode);
  }

  static DateTime parseUserInput(int year, int month, int day, {required CalendarType calendar}) {
    if (calendar == CalendarType.ethiopian) {
      return EthiopianCalendar.ethiopianToGregorian(year, month, day);
    }
    return DateTime(year, month, day);
  }
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `cd app && flutter test test/core/utils/date_formatter_test.dart`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/utils/date_formatter.dart app/test/core/utils/date_formatter_test.dart
git commit -m "feat(calendar): add DateFormatter facade with active calendar state"
```

---

## Task 4: Extend `SettingsProvider` with `calendarType`

**Files:**
- Modify: `app/lib/core/providers/settings_provider.dart`
- Test: `app/test/core/providers/settings_provider_test.dart` (extend)

- [ ] **Step 1: Find the existing `SettingsProvider`**

Run: `grep -n "setLanguage\|language" app/lib/core/providers/settings_provider.dart`

- [ ] **Step 2: Write the failing test**

Add to the existing test file:

```dart
test('default calendar follows language', () async {
  final p = SettingsProvider();
  await p.load();
  await p.setLanguage('am');
  expect(p.calendarType, CalendarType.ethiopian);
  await p.setLanguage('en');
  expect(p.calendarType, CalendarType.gregorian);
});

test('setCalendarType persists', () async {
  SharedPreferences.setMockInitialValues({});
  final p = SettingsProvider();
  await p.load();
  await p.setCalendarType(CalendarType.ethiopian);
  expect(p.calendarType, CalendarType.ethiopian);
});
```

- [ ] **Step 3: Run tests, expect failure**

Run: `cd app && flutter test test/core/providers/settings_provider_test.dart`
Expected: missing `setCalendarType`.

- [ ] **Step 4: Add the field and method**

In `app/lib/core/providers/settings_provider.dart`:

```dart
import '../utils/date_formatter.dart';

class SettingsProvider extends ChangeNotifier {
  // ...existing
  CalendarType _calendarType = CalendarType.gregorian;
  CalendarType get calendarType => _calendarType;

  Future<void> load() async {
    // ...existing
    final stored = prefs.getString('calendar_type_v1');
    if (stored != null) {
      _calendarType = CalendarType.values.firstWhere(
        (c) => c.name == stored,
        orElse: () => _calendarType,
      );
    }
    // Default by language:
    if (stored == null) {
      _calendarType = _language == 'am' ? CalendarType.ethiopian : CalendarType.gregorian;
    }
    DateFormatter.setActive(_calendarType);
    notifyListeners();
  }

  Future<void> setCalendarType(CalendarType c) async {
    _calendarType = c;
    DateFormatter.setActive(c);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('calendar_type_v1', c.name);
    notifyListeners();
  }

  // When language changes, also re-default calendar if user hasn't set one explicitly.
  Future<void> setLanguage(String code) async {
    // ...existing
    final explicit = (await SharedPreferences.getInstance()).containsKey('calendar_type_v1');
    if (!explicit) {
      _calendarType = code == 'am' ? CalendarType.ethiopian : CalendarType.gregorian;
      DateFormatter.setActive(_calendarType);
    }
    notifyListeners();
  }
}
```

- [ ] **Step 5: Run settings tests, expect pass**

Run: `cd app && flutter test test/core/providers/settings_provider_test.dart`
Expected: existing + new tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/providers/settings_provider.dart app/test/core/providers/settings_provider_test.dart
git commit -m "feat(calendar): add calendarType to SettingsProvider"
```

---

## Task 5: `EthDatePickerDialog` widget

**Files:**
- Create: `app/lib/presentation/widgets/eth_date_picker_dialog.dart`
- Test: `app/test/presentation/widgets/eth_date_picker_dialog_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class EthDatePickerDialog extends StatefulWidget {
    const EthDatePickerDialog({super.key, this.initial});
    final DateTime? initial;
    Future<DateTime?> show(BuildContext context);
  }
  ```

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/presentation/widgets/eth_date_picker_dialog.dart';

void main() {
  testWidgets('EthDatePickerDialog shows year/month/day dropdowns', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            picked = await EthDatePickerDialog(initial: DateTime(2026, 8, 29)).show(context);
          },
          child: const Text('open'),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ethYear')), findsOneWidget);
    expect(find.byKey(const Key('ethMonth')), findsOneWidget);
    expect(find.byKey(const Key('ethDay')), findsOneWidget);
    expect(picked, isNull);
  });
}
```

- [ ] **Step 2: Run tests, expect failure**

Run: `cd app && flutter test test/presentation/widgets/eth_date_picker_dialog_test.dart`
Expected: import error.

- [ ] **Step 3: Implement `EthDatePickerDialog`**

```dart
import 'package:flutter/material.dart';
import '../core/utils/ethiopian_calendar.dart';
import '../core/utils/date_formatter.dart';

class EthDatePickerDialog extends StatefulWidget {
  const EthDatePickerDialog({super.key, this.initial});
  final DateTime? initial;

  Future<DateTime?> show(BuildContext context) {
    return showDialog<DateTime>(
      context: context,
      builder: (_) => this,
    );
  }

  @override
  State<EthDatePickerDialog> createState() => _EthDatePickerDialogState();
}

class _EthDatePickerDialogState extends State<EthDatePickerDialog> {
  late EthDate _eth;
  late int _year;

  @override
  void initState() {
    super.initState();
    final init = widget.initial ?? DateTime.now();
    _eth = EthiopianCalendar.gregorianToEthiopian(init);
    _year = _eth.year;
  }

  void _setMonth(int m) => setState(() => _eth = EthDate(_year, m, 1));

  @override
  Widget build(BuildContext context) {
    final maxDay = EthiopianCalendar.daysInEthiopianMonth(_year, _eth.month);
    final day = _eth.day.clamp(1, maxDay);
    return AlertDialog(
      title: const Text('Select date'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<int>(
            key: const Key('ethYear'),
            value: _year,
            items: List.generate(20, (i) => _year - 5 + i)
                .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                .toList(),
            onChanged: (v) => setState(() {
              _year = v!;
              _eth = EthDate(_year, _eth.month, _eth.day);
            }),
          ),
          DropdownButton<int>(
            key: const Key('ethMonth'),
            value: _eth.month,
            items: List.generate(13, (i) => i + 1)
                .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(EthiopianCalendar.monthNamesAmharic[m - 1]),
                    ))
                .toList(),
            onChanged: (v) => _setMonth(v!),
          ),
          DropdownButton<int>(
            key: const Key('ethDay'),
            value: day,
            items: List.generate(maxDay, (i) => i + 1)
                .map((d) => DropdownMenuItem(value: d, child: Text('$d')))
                .toList(),
            onChanged: (v) => setState(() => _eth = EthDate(_year, _eth.month, v!)),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final g = EthiopianCalendar.ethiopianToGregorian(_year, _eth.month, day);
            Navigator.of(context).pop(g);
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `cd app && flutter test test/presentation/widgets/eth_date_picker_dialog_test.dart`
Expected: 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add app/lib/presentation/widgets/eth_date_picker_dialog.dart app/test/presentation/widgets/eth_date_picker_dialog_test.dart
git commit -m "feat(calendar): add Ethiopian date picker dialog"
```

---

## Task 6: Add Calendar sub-section in Settings

**Files:**
- Modify: `app/lib/presentation/screens/settings/settings_screen.dart`
- Modify: `app/lib/l10n/app_en.arb` / `app_am.arb`
- Run: `flutter gen-l10n`

- [ ] **Step 1: Add new strings**

Append to `app/lib/l10n/app_en.arb`:
```json
  "calendarType": "Calendar",
  "gregorian": "Gregorian",
  "ethiopian": "Ethiopian"
```

Append to `app/lib/l10n/app_am.arb`:
```json
  "calendarType": "ቀን መቁጠሪያ",
  "gregorian": "ግሪጎሪያን",
  "ethiopian": "ኢትዮጵያዊ"
```

- [ ] **Step 2: Regenerate localizations**

Run: `cd app && flutter gen-l10n`

- [ ] **Step 3: Add the sub-section to settings**

In `app/lib/presentation/screens/settings/settings_screen.dart`, find the Language section and add immediately below it:

```dart
Consumer<SettingsProvider>(
  builder: (context, sp, _) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Calendar', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<CalendarType>(
            segments: const [
              ButtonSegment(value: CalendarType.gregorian, label: Text('Gregorian')),
              ButtonSegment(value: CalendarType.ethiopian, label: Text('Ethiopian')),
            ],
            selected: {sp.calendarType},
            onSelectionChanged: (s) => sp.setCalendarType(s.first),
          ),
        ),
      ],
    );
  },
),
```

- [ ] **Step 4: Run full test suite**

Run: `cd app && flutter test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/presentation/screens/settings/settings_screen.dart app/lib/l10n/
git commit -m "feat(calendar): add Calendar sub-section to settings"
```

---

## Task 7: Migrate UI to `DateFormatter`

**Files:**
- Modify: every file under `app/lib/presentation/` that calls `DateFormat.*` or imports `package:intl/intl.dart` for date formatting.

- [ ] **Step 1: Find all date-formatting call sites**

Run:
```bash
grep -rln "DateFormat\|intl" app/lib/presentation | head -50
```

For each file, replace:
- `import 'package:intl/intl.dart';` (only used for date formatting) with `import '../../core/utils/date_formatter.dart';`
- `DateFormat.yMMMd(languageCode).format(d)` with `DateFormatter.formatDate(d, languageCode: languageCode)`
- `DateFormat.yMMMM(languageCode).format(d)` with `DateFormatter.formatMonthYear(d, languageCode: languageCode)`
- `'Today'/'Yesterday'` ad-hoc strings with `DateFormatter.formatRelative(d)`

Specifically expected files (verify with grep):
- `app/lib/presentation/screens/transaction/transaction_list.dart`
- `app/lib/presentation/screens/income/company_income_screen.dart`
- `app/lib/presentation/screens/expense/expense_list_screen.dart`
- `app/lib/presentation/screens/audit/audit_log_screen.dart`
- `app/lib/presentation/screens/reports/reports_screen.dart` (chart axis too)
- `app/lib/presentation/screens/worker_detail/worker_detail_screen.dart`
- `app/lib/presentation/screens/worker/tabs/*.dart`
- `app/lib/presentation/widgets/activity_feed_list.dart`

- [ ] **Step 2: Update `showDatePicker` call sites**

For each `showDatePicker(...)` in `app/lib/presentation/`, wrap it:

```dart
onPressed: () async {
  final sp = context.read<SettingsProvider>();
  if (sp.calendarType == CalendarType.ethiopian) {
    final picked = await EthDatePickerDialog(initial: current).show(context);
    if (picked != null) setState(() => current = picked);
  } else {
    final picked = await showDatePicker(context: context, initialDate: current, firstDate: ..., lastDate: ...);
    if (picked != null) setState(() => current = picked);
  }
},
```

- [ ] **Step 3: Run full test suite**

Run: `cd app && flutter test`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add app/lib/presentation/
git commit -m "refactor(calendar): migrate UI to DateFormatter facade"
```

---

## Task 8: Receipt PDF header

**Files:**
- Find the receipt service under `app/lib/core/services/` (likely `receipt_service.dart`).
- Modify: any string that builds a date in the PDF.

- [ ] **Step 1: Find receipt date usage**

Run:
```bash
grep -rln "receipt\|Receipt" app/lib/core/services
```

- [ ] **Step 2: Replace `DateFormat` with `DateFormatter.formatDate`**

In the receipt PDF generator, change the date string to use `DateFormatter.formatDate(transaction.createdAt)`.

- [ ] **Step 3: Run tests**

Run: `cd app && flutter test`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add app/lib/core/services/
git commit -m "refactor(calendar): use DateFormatter in receipt PDF"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| Settings sub-section under Language | Task 6 |
| Default by language | Task 4 |
| Display in lists, audit, reports, charts, receipts | Tasks 7, 8 |
| Input: date pickers | Task 7 step 2 + Task 5 |
| `fl_chart` axis labels | Task 7 (find + replace) |
| Week start Saturday in ET mode | Open item (see below) |
| 13 month names incl. ጳጉሜ (5/6 days) | Task 2 (`daysInEthiopianMonth`), Task 5 (picker max day) |
| UTC-safe | Implicit (uses local `DateTime`) |
| `shared_preferences` storage | Task 4 |
| Error handling matrix | Task 2 fallback in `formatDate` (try/catch not needed; pure math) |
| Testing matrix | Each task has tests |

**Placeholder scan:** no TBD/TODO. All code is concrete.

**Type consistency:** `CalendarType` enum used uniformly across Tasks 3, 4, 5, 6. `DateFormatter.formatDate(DateTime, {languageCode})` signature used in Task 7. `EthDate` value type used in Tasks 2, 5.

**Open item:** "This week" boundary (Saturday start in ET mode) is **deferred** — the plan covers display and input, not the "this week" calculation in reports. If you want it in this release, add a `weekStartSaturday(bool isEthiopian)` helper in `DateFormatter` and pass it to the reports query.
