import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color primary = Color(0xFFD47311);
  static const Color backgroundLight = Color(0xFFFAFAFB); // Whitish grey
  static const Color backgroundDark = Color(0xFF221910);
  static const Color surfaceDark = Color(0xFF2A1D13);
  static const Color surfaceLight = Color(0xFFFFFFFF);

  static const Color textMutedDark = Color(0xFFC9AD92); // "Latte" text
  static const Color textMutedLight = Color(0xFF64748B); // Slate-500 equivalent

  static const Color success = Color(0xFF22C55E); // Green-500
  static const Color error = Color(0xFFEF4444); // Red-500
}

class AppTheme {
  static const String _fontFamily = 'DMSans';

  static TextTheme _dmSansTextTheme(Color color) {
    return GoogleFonts.dmSansTextTheme().apply(
      bodyColor: color,
      displayColor: color,
    );
  }

  /// Smooth fade-and-lift transition used on every platform.
  ///
  /// Only the incoming route animates (fades in + drifts up slightly) while
  /// the route beneath stays fully opaque, so the app background is never
  /// exposed mid-transition — no white/black flash in any theme.
  static final PageTransitionsTheme _pageTransitions = PageTransitionsTheme(
    builders: {
      for (final platform in TargetPlatform.values)
        platform: _AppFadePageTransitionsBuilder(),
    },
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: _fontFamily,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.backgroundLight,
      canvasColor: AppColors.backgroundLight,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        surface: AppColors.surfaceLight,
        onSurface: Colors.black87,
      ),
      pageTransitionsTheme: _pageTransitions,
      textTheme: _dmSansTextTheme(Colors.black87),
      iconTheme: const IconThemeData(color: Colors.black87),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: _fontFamily,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      canvasColor: AppColors.backgroundDark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        surface: AppColors.surfaceDark,
        onSurface: Colors.white,
      ),
      cardColor: AppColors.surfaceDark,
      pageTransitionsTheme: _pageTransitions,
      textTheme: _dmSansTextTheme(Colors.white),
      iconTheme: const IconThemeData(color: Colors.white),
    );
  }
}

class _AppFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _AppFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
