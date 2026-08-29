import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cofiz/l10n/app_localizations.dart';
import '../../../core/providers/phone_otp_auth_provider.dart';
import '../../../core/services/auth_backend.dart';
import '../../../core/utils/phone_utils.dart';
import 'otp_verify_screen.dart';
import 'bot_opt_in_banner.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});
  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  static const String _telegramBotId = String.fromEnvironment(
    'TELEGRAM_BOT_ID',
    defaultValue: '',
  );

  final _phoneCtl = TextEditingController();
  OtpProvider _provider = OtpProvider.whatsapp;
  bool _sending = false;

  @override
  void dispose() {
    _phoneCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _phoneCtl.text.trim();
    final phone = isValidE164(raw) ? raw : normalizeE164(raw);
    if (!isValidE164(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid phone number (e.g. +251911234567)')),
      );
      return;
    }
    setState(() => _sending = true);
    final p = context.read<PhoneOtpAuthProvider>();
    await p.requestOtp(phone: phone, provider: _provider);
    if (!mounted) return;
    setState(() => _sending = false);
    if (p.state == OtpAuthState.awaitingCode) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OtpVerifyScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(p.lastErrorMessage ?? 'Could not send code')),
      );
    }
  }

  Future<void> _continueWithTelegram() async {
    if (_telegramBotId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telegram sign-in is not configured.')),
      );
      return;
    }
    final url =
        'https://oauth.telegram.org/auth?bot_id=$_telegramBotId'
        '&origin=${Uri.encodeComponent('cofiz')}'
        '&return_to=${Uri.encodeComponent('cofiz://auth/telegram')}'
        '&request_access=write';
    // Telegram posts back to cofiz://auth/telegram when the user signs in;
    // TelegramLoginListener (mounted at app root) picks it up and calls
    // completeTelegramLogin on the provider.
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Telegram.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Telegram one-tap sign-in. No phone number needed.
            OutlinedButton.icon(
              key: const Key('continueWithTelegramButton'),
              icon: const Icon(Icons.telegram),
              label: const Text('Continue with Telegram'),
              onPressed: _continueWithTelegram,
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            SegmentedButton<OtpProvider>(
              segments: [
                ButtonSegment(value: OtpProvider.telegram, label: Text(t.providerTelegram)),
                ButtonSegment(value: OtpProvider.whatsapp, label: Text(t.providerWhatsapp)),
              ],
              selected: {_provider},
              onSelectionChanged: (s) => setState(() => _provider = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneCtl,
              decoration: InputDecoration(labelText: t.enterPhoneNumber),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            BotOptInBanner(
              deepLink: _provider == OtpProvider.telegram
                  ? 'https://t.me/cofiz_bot?start=${Uri.encodeComponent(_phoneCtl.text)}'
                  : 'https://wa.me/255700000000?text=START',
              providerLabel: _provider.name,
            ),
            const Spacer(),
            FilledButton(
              key: const Key('sendCodeButton'),
              onPressed: _sending ? null : _submit,
              child: Text(t.sendCode),
            ),
          ],
        ),
      ),
    );
  }
}
