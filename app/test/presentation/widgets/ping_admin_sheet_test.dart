import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/user_model.dart';
import 'package:cofiz/presentation/widgets/ping_admin_sheet.dart';

void main() {
  group('PingAdminSheet', () {
    testWidgets('collector sheet shows Need cash preset', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => showPingAdminSheet(c, UserRole.worker),
              child: const Text('x'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pumpAndSettle();

      expect(find.text('Need cash'), findsOneWidget);
      expect(find.text('Issue with record'), findsOneWidget);
      expect(find.text('Report ready'), findsOneWidget);
      expect(find.text('Need clarification'), findsNothing);
    });

    testWidgets('viewer sheet shows Need clarification preset', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => showPingAdminSheet(c, UserRole.viewer),
              child: const Text('x'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pumpAndSettle();

      expect(find.text('Need clarification'), findsOneWidget);
      expect(find.text('Report looks off'), findsOneWidget);
      expect(find.text('Request summary'), findsOneWidget);
      expect(find.text('Need cash'), findsNothing);
    });

    testWidgets('sheet has free text with counter and 120 limit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => showPingAdminSheet(c, UserRole.worker),
              child: const Text('x'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      // counter should show 0/120 initially
      expect(find.textContaining('0/120'), findsOneWidget);

      // typing updates counter
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(find.textContaining('5/120'), findsOneWidget);

      final TextField tf = tester.widget(find.byType(TextField));
      expect(tf.maxLength, 120);
    });

    testWidgets('chip tap fills text field', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => showPingAdminSheet(c, UserRole.worker),
              child: const Text('x'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Need cash'));
      await tester.pump();
      final TextField tf = tester.widget(find.byType(TextField));
      expect(tf.controller?.text, 'Need cash');
    });

    testWidgets('Send disabled when text empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => showPingAdminSheet(c, UserRole.worker),
              child: const Text('x'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pumpAndSettle();

      final sendFinder = find.text('Send');
      expect(sendFinder, findsOneWidget);
      final ElevatedButton btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Send'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('Send enabled when text entered', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => showPingAdminSheet(c, UserRole.worker),
              child: const Text('x'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      final ElevatedButton btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Send'),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('Send disabled when offline', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => showPingAdminSheet(
                c,
                UserRole.worker,
                isOnline: () => false,
              ),
              child: const Text('x'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      final ElevatedButton btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Send'),
      );
      expect(btn.onPressed, isNull);
      expect(find.textContaining('offline'), findsOneWidget);
    });

    testWidgets('uses DraggableScrollableSheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => showPingAdminSheet(c, UserRole.worker),
              child: const Text('x'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pumpAndSettle();

      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    });

    testWidgets('admin role shows no presets or defaults to collector', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => showPingAdminSheet(c, UserRole.admin),
              child: const Text('x'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pumpAndSettle();

      // admin should not be used for ping; sheet still renders but no collector/viewer presets
      // whichever implementation, ensure TextField exists
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
