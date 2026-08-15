import 'package:intl/intl.dart';

class NumberFormatter {
  static final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _currencyFormatDecimal =
      NumberFormat('#,##0.00', 'en_US');
  static final NumberFormat _weightFormat = NumberFormat('#,##0.0', 'en_US');

  static String format(num value) {
    return _currencyFormat.format(value);
  }

  static String formatDecimal(num value) {
    return _currencyFormatDecimal.format(value);
  }

  static String formatWeight(num value) {
    return _weightFormat.format(value);
  }

  static String formatCurrency(num value, {String currency = 'ETB'}) {
    return '$currency ${format(value)}';
  }

  static String formatCurrencyDecimal(num value, {String currency = 'ETB'}) {
    return '$currency ${formatDecimal(value)}';
  }

  static String formatCompact(num value) {
    final abs = value.abs();
    if (abs >= 1000000000) {
      return '${_trimTrailingZero(value / 1000000000)}B';
    } else if (abs >= 1000000) {
      return '${_trimTrailingZero(value / 1000000)}M';
    } else if (abs >= 1000) {
      return '${_trimTrailingZero(value / 1000)}K';
    }
    return format(value);
  }

  static String _trimTrailingZero(num value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }
}

extension NumFormatting on num {
  String get formatted => NumberFormatter.format(this);

  String get formattedDecimal => NumberFormatter.formatDecimal(this);

  String get asCurrency => NumberFormatter.formatCurrency(this);

  String get asWeight => '${NumberFormatter.formatWeight(this)} Kg';

  String get formattedCompact => NumberFormatter.formatCompact(this);
}