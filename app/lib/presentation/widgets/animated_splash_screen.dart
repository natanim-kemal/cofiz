import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';

/// Branded startup splash shown while the app boots and auth state loads.
///
/// The logo starts small, blurred and faint, then comes toward the viewer:
/// it scales up to a comfortable size, sharpens and fades to full opacity.
class AnimatedSplashScreen extends StatelessWidget {
  const AnimatedSplashScreen({super.key});

  static const Duration animationDuration = Duration(milliseconds: 950);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF221910) : theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          Center(
            child: Image.asset(
              'assets/icon-bgless.png',
              width: 110,
              height: 110,
              fit: BoxFit.contain,
            )
                .animate(
                  onPlay: (controller) => controller.forward(),
                )
                .fade(
                  begin: 0.15,
                  end: 1,
                  duration: animationDuration,
                  curve: Curves.easeOut,
                )
                .scale(
                  begin: const Offset(0.35, 0.35),
                  end: const Offset(1, 1),
                  duration: animationDuration,
                  curve: Curves.easeOutCubic,
                )
                .blur(
                  begin: const Offset(20, 20),
                  end: Offset.zero,
                  duration: animationDuration,
                  curve: Curves.easeOut,
                ),
          ),
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Text(
              'Cofiz',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: AppColors.primary,
              ),
            )
                .animate(
                  onPlay: (controller) => controller.forward(),
                )
                .fadeIn(
                  delay: 500.ms,
                  duration: 500.ms,
                )
                .slideY(begin: 0.4, end: 0),
          ),
        ],
      ),
    );
  }
}
