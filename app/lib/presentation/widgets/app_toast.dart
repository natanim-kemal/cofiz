import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppToastData {
  final String message;
  final bool success;
  final int id;

  const AppToastData({
    required this.message,
    required this.success,
    required this.id,
  });
}

class AppToast {
  static final ValueNotifier<AppToastData?> _notifier = ValueNotifier(null);
  static int _counter = 0;

  static void show(String message, {bool success = false}) {
    _notifier.value = AppToastData(
      message: message,
      success: success,
      id: _counter++,
    );
  }

  static ValueListenable<AppToastData?> get notifier => _notifier;
}

class AppToastHost extends StatefulWidget {
  final Widget child;

  const AppToastHost({super.key, required this.child});

  @override
  State<AppToastHost> createState() => _AppToastHostState();
}

class _AppToastHostState extends State<AppToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  AppToastData? _current;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    AppToast.notifier.addListener(_onToast);
  }

  @override
  void dispose() {
    AppToast.notifier.removeListener(_onToast);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onToast() {
    final toast = AppToast.notifier.value;
    if (toast == null) return;
    _timer?.cancel();
    setState(() => _current = toast);
    _controller.forward(from: 0);
    _timer = Timer(const Duration(seconds: 3), _dismiss);
  }

  void _dismiss() {
    _timer?.cancel();
    _controller.reverse().whenComplete(() {
      if (mounted) setState(() => _current = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        widget.child,
        if (_current != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position: _slide,
                        child: GestureDetector(
                          onTap: _dismiss,
                          child: _buildCard(context, _current!, isDark),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, AppToastData toast, bool isDark) {
    final success = toast.success;
    final bg = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final fg = isDark ? Colors.white : Colors.black87;
    final iconColor = success
        ? (isDark ? const Color(0xFFA5D6A7) : const Color(0xFF2E7D32))
        : (isDark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828));

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon-bgless.png',
                width: 26,
                height: 26,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  success ? Icons.check_circle : Icons.error,
                  color: iconColor,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                toast.message,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.close, color: fg.withOpacity(0.6), size: 16),
          ],
        ),
      ),
    );
  }
}
