import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cofiz/l10n/app_localizations.dart';
import '../../../core/providers/phone_otp_auth_provider.dart';

class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({super.key});
  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _digits = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _digits) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _digits.map((c) => c.text).join();
    if (code.length != 6) return;
    final p = context.read<PhoneOtpAuthProvider>();
    await p.verifyOtp(code: code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
            return SizedBox(
              width: 40,
              child: TextField(
                key: Key('codeDigit$i'),
                controller: _digits[i],
                focusNode: _focusNodes[i],
                keyboardType: TextInputType.number,
                maxLength: 1,
                textAlign: TextAlign.center,
                onChanged: (v) {
                  if (v.isNotEmpty && i < 5) _focusNodes[i + 1].requestFocus();
                  if (i == 5 && _digits.every((c) => c.text.isNotEmpty)) _submit();
                },
              ),
            );
          }),
        ),
      ),
    );
  }
}
