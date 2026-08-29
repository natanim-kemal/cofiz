import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/phone_otp_auth_provider.dart';
import '../../../core/services/auth_backend.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/background_pattern.dart';
import '../../widgets/app_toast.dart';
import 'otp_verify_screen.dart';
import 'bot_opt_in_banner.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});
  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  static const String _telegramBotId = String.fromEnvironment('TELEGRAM_BOT_ID', defaultValue: '');
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
      AppToast.show('Enter a valid phone number (e.g. +251911234567)');
      return;
    }
    setState(() => _sending = true);
    final p = context.read<PhoneOtpAuthProvider>();
    await p.requestOtp(phone: phone, provider: _provider);
    if (!mounted) return;
    setState(() => _sending = false);
    if (p.state == OtpAuthState.awaitingCode) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OtpVerifyScreen()));
    } else {
      AppToast.show(p.lastErrorMessage ?? 'Could not send code');
    }
  }

  Future<void> _continueWithTelegram() async {
    if (_telegramBotId.isEmpty) {
      AppToast.show('Telegram sign-in is not configured.');
      return;
    }
    final url =
        'https://oauth.telegram.org/auth?bot_id=$_telegramBotId&origin=${Uri.encodeComponent('cofiz')}&return_to=${Uri.encodeComponent('cofiz://auth/telegram')}&request_access=write';
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) AppToast.show('Could not open Telegram.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          const BackgroundPattern(),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    Align(
                      alignment: Alignment.center,
                      child: Image.asset('assets/icon-bgless.png', width: 72, height: 72, fit: BoxFit.contain),
                    ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.92, 0.92)),
                    const SizedBox(height: 20),
                    Text(
                      l10n.welcome,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in with phone',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                    ).animate().fadeIn(delay: 150.ms),
                    const SizedBox(height: 32),
                    OutlinedButton.icon(
                      key: const Key('continueWithTelegramButton'),
                      icon: const Icon(Icons.telegram, color: AppColors.primary),
                      label: Text('Continue with Telegram', style: TextStyle(fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: isDark ? Colors.white24 : Colors.black.withOpacity(0.12)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
                      ),
                      onPressed: _continueWithTelegram,
                    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.05, end: 0),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: Divider(color: isDark ? Colors.white12 : Colors.black12)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or', style: theme.textTheme.bodySmall?.copyWith(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                      ),
                      Expanded(child: Divider(color: isDark ? Colors.white12 : Colors.black12)),
                    ]),
                    const SizedBox(height: 16),
                    SegmentedButton<OtpProvider>(
                      segments: [
                        ButtonSegment(value: OtpProvider.telegram, label: Text(l10n.providerTelegram)),
                        ButtonSegment(value: OtpProvider.whatsapp, label: Text(l10n.providerWhatsapp)),
                      ],
                      selected: {_provider},
                      onSelectionChanged: (s) => setState(() => _provider = s.first),
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) return AppColors.primary.withOpacity(0.14);
                          return isDark ? AppColors.surfaceDark : Colors.white;
                        }),
                      ),
                    ).animate().fadeIn(delay: 240.ms),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneCtl,
                      keyboardType: TextInputType.phone,
                      style: theme.textTheme.bodyMedium?.copyWith(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
                      cursorColor: AppColors.primary,
                      decoration: InputDecoration(
                        labelText: l10n.enterPhoneNumber,
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                        filled: true,
                        fillColor: isDark ? AppColors.surfaceDark : Colors.white,
                        labelStyle: theme.textTheme.bodyMedium?.copyWith(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight, fontSize: 14),
                        floatingLabelStyle: theme.textTheme.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        prefixIconColor: AppColors.primary,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
                        ),
                      ),
                    ).animate().fadeIn(delay: 280.ms).slideY(begin: 0.05, end: 0),
                    const SizedBox(height: 12),
                    BotOptInBanner(
                      deepLink: _provider == OtpProvider.telegram
                          ? 'https://t.me/cofiz_bot?start=${Uri.encodeComponent(_phoneCtl.text)}'
                          : 'https://wa.me/255700000000?text=START',
                      providerLabel: _provider.name,
                    ).animate().fadeIn(delay: 320.ms),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        key: const Key('sendCodeButton'),
                        onPressed: _sending ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _sending
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(l10n.sendCode, style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ).animate().fadeIn(delay: 360.ms).slideY(begin: 0.1, end: 0),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Back to email sign-in',
                            style: theme.textTheme.bodySmall?.copyWith(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
