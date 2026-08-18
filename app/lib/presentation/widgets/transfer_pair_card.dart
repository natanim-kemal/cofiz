import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class TransferPairCard<T> extends StatefulWidget {
  final T first;
  final T second;
  final Widget Function(
    T item, {
    double bottomMargin,
    VoidCallback? onTapOverride,
  }) buildRow;

  const TransferPairCard({
    super.key,
    required this.first,
    required this.second,
    required this.buildRow,
  });

  @override
  State<TransferPairCard<T>> createState() => _TransferPairCardState<T>();
}

class _TransferPairCardState<T> extends State<TransferPairCard<T>> {
  static const double _overlapY = 26;
  static const double _overlapX = -10;
  static const double _gap = 20;

  bool _spread = false;
  double _cardHeight = 72;
  final GlobalKey _measureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    final ctx = _measureKey.currentContext;
    if (ctx == null || !mounted) return;
    final h = ctx.size?.height ?? 0;
    if (h != _cardHeight) setState(() => _cardHeight = h);
  }

  void _spreadTap() => setState(() => _spread = true);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height =
            _spread ? _cardHeight * 2 + _gap : _cardHeight + _overlapY;
        final spreadTap = _spread ? null : _spreadTap;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  key: _measureKey,
                  left: 0,
                  top: 0,
                  width: width,
                  child: widget.buildRow(
                    widget.first,
                    bottomMargin: 0,
                    onTapOverride: spreadTap,
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: _spread ? 0 : _overlapX,
                  top: _spread ? _cardHeight + _gap : _overlapY,
                  width: width,
                  child: widget.buildRow(
                    widget.second,
                    bottomMargin: 0,
                    onTapOverride: spreadTap,
                  ),
                ),
                if (_spread)
                  Positioned(
                    left: 0,
                    top: _cardHeight,
                    width: width,
                    height: _gap,
                    child: _buildPairConnector(context),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPairConnector(BuildContext context) {
    const warmOrange = AppColors.primary;
    return InkWell(
      onTap: () => setState(() => _spread = false),
      child: Row(
        children: [
          const SizedBox(width: 36),
          Container(width: 2, color: warmOrange.withOpacity(0.4)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.expand_less, size: 14, color: warmOrange),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
