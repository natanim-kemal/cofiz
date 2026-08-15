import 'package:flutter/material.dart';

class BackgroundPattern extends StatelessWidget {
  final Widget? child;
  final double opacity;

  const BackgroundPattern({
    super.key,
    this.child,
    this.opacity = 0.1, //
  });

  @override
  Widget build(BuildContext context) {
    return child ?? const SizedBox.expand();
  }
}

class DotPatternPainter extends CustomPainter {
  final Color color;
  final double spacing;
  final double radius;

  DotPatternPainter({
    required this.color,
    this.spacing = 20.0,
    this.radius = 1.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        final xOffset = (y / spacing).round() % 2 == 0 ? 0.0 : spacing / 2;

        canvas.drawCircle(
          Offset(x + xOffset, y),
          radius,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant DotPatternPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.spacing != spacing ||
        oldDelegate.radius != radius;
  }
}
