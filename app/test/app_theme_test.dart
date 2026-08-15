import 'package:cofiz/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';

void main() {
  testWidgets('explicit text styles inherit the bundled DM Sans family', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Text(
            'DM Sans',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    expect(paragraph.text.style?.fontFamily, startsWith('DMSans'));
    expect(paragraph.text.style?.fontWeight, FontWeight.w600);
  });
}
