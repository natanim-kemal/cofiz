import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/presentation/widgets/app_toast.dart';
import 'package:cofiz/presentation/widgets/double_back_exit.dart';

void main() {
  var fakeNow = DateTime(2026, 8, 17, 10, 0, 0);

  Widget buildApp() {
    return MaterialApp(
      home: AppToastHost(
        child: DoubleBackExit(
          now: () => fakeNow,
          child: const Scaffold(body: Center(child: Text('Home'))),
        ),
      ),
    );
  }

  testWidgets('first back press shows tap-again toast', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Tap back again to exit'), findsOneWidget);
    // Still on the same screen - did not leave.
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('second back press within window exits the app', (tester) async {
    var popped = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') popped = true;
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(buildApp());

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));

    // Second press within the 2s window.
    fakeNow = fakeNow.add(const Duration(seconds: 1));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));

    expect(popped, isTrue);
  });

  testWidgets('back press after the window shows toast again', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tap back again to exit'), findsOneWidget);

    // Advance past the 2s exit window; toast auto-dismisses.
    fakeNow = fakeNow.add(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Tap back again to exit'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });
}
