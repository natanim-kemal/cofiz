import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class CustomHeader extends StatelessWidget {
  final Widget child;
  final double height;
  final Color? backgroundColor;

  const CustomHeader({
    super.key,
    required this.child,
    this.height = 200,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 10, 20, 20),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.primary,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: child,
    );
  }
}
