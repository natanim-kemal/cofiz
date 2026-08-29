import 'dart:convert';
import 'package:crypto/crypto.dart';

final _e164 = RegExp(r'^\+[1-9]\d{7,14}$');

bool isValidE164(String phone) => _e164.hasMatch(phone);

String normalizeE164(String raw, {String defaultRegion = 'ET'}) {
  final trimmed = raw.replaceAll(RegExp(r'[\s-]'), '');
  if (trimmed.startsWith('+')) return trimmed;
  switch (defaultRegion) {
    case 'ET':
      final local = trimmed.startsWith('0') ? trimmed.substring(1) : trimmed;
      return '+$defaultRegion$local'
          .replaceFirst('+ET', '+251');
  }
  return '+$trimmed';
}

String sha256Hex(String input) {
  final digest = sha256.convert(utf8.encode(input));
  return digest.toString();
}
