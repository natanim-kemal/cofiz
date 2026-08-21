import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/presentation/widgets/animated_splash_screen.dart';

void main() {
  testWidgets('AnimatedSplashScreen renders the logo and brand name',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AnimatedSplashScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Cofiz'), findsOneWidget);
  });

  testWidgets('AnimatedSplashScreen stays visible after animation completes',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AnimatedSplashScreen()),
    );

    await tester.pump(AnimatedSplashScreen.animationDuration);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Cofiz'), findsOneWidget);
  });
}