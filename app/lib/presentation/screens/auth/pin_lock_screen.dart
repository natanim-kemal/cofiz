import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/lock_state_provider.dart';
import '../../../core/providers/phone_otp_auth_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/background_pattern.dart';
import '../../widgets/app_toast.dart';

class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});
  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final _digits = List.generate(6, (_) => TextEditingController());
  final _focus = List.generate(6, (_) => FocusNode());
  bool _submitting = false;
  String? _error;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    try {
      final auth = LocalAuthentication();
      final can = await auth.canCheckBiometrics;
      final available = await auth.isDeviceSupported();
      if (mounted) setState(() => _biometricAvailable = can && available);
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in _digits) c.dispose();
    for (final f in _focus) f.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _digits.map((c) => c.text).join();
    if (code.length != 6) return;
    final lsp = context.read<LockStateProvider>();
    if (lsp.isInCooldown) {
      final secs = lsp.cooldownRemaining?.inSeconds ?? 0;
      setState(() => _error = AppLocalizations.of(context)!.cooldownWait(secs.toString()));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok = await lsp.attemptUnlock(code);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    if (ok) {
      // Pop handled by caller — PinLockScreen is shown as overlay via lock state
      // For now, just clear fields. Parent (AuthGate) will rebuild to home.
      setState(() => _submitting = false);
      return;
    }
    if (lsp.shouldForceSignOut) {
      AppToast.show(l10n.pinTooMany);
      await context.read<PhoneOtpAuthProvider>().signOut();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    if (lsp.isInCooldown) {
      final secs = lsp.cooldownRemaining?.inSeconds ?? 0;
      setState(() {
        _error = l10n.cooldownWait(secs.toString());
        _submitting = false;
      });
      return;
    }
    setState(() {
      _error = l10n.pinIncorrect;
      _submitting = false;
      // clear for retry
      for (final c in _digits) c.clear();
      _focus[0].requestFocus();
    });
  }

  Future<void> _useBiometric() async {
    final auth = LocalAuthentication();
    try {
      final ok = await auth.authenticate(
        localizedReason: 'Unlock Cofiz',
        biometricOnly: true,
      );
      if (ok && mounted) {
        context.read<LockStateProvider>().unlockWithBiometric();
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Biometric failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final lsp = context.watch<LockStateProvider>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          const BackgroundPattern(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                        ),
                        child: const Icon(Icons.lock_rounded, size: 36, color: AppColors.primary),
                      ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.92, 0.92)),
                      const SizedBox(height: 16),
                      Text(
                        l10n.pinLockTitle,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ).animate().fadeIn(delay: 80.ms),
                      const SizedBox(height: 6),
                      Text(
                        l10n.pinLockSubtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                        ),
                      ).animate().fadeIn(delay: 120.ms),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (i) {
                          final hasValue = _digits[i].text.isNotEmpty;
                          final isError = _error != null;
                          return SizedBox(
                            width: 46,
                            height: 56,
                            child: TextField(
                              key: Key('pinDigit$i'),
                              controller: _digits[i],
                              focusNode: _focus[i],
                              maxLength: 1,
                              obscureText: true,
                              obscuringCharacter: '●',
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              enabled: !_submitting && !lsp.isInCooldown,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                counterText: '',
                                filled: true,
                                fillColor: isDark ? AppColors.surfaceDark : Colors.white,
                                contentPadding: EdgeInsets.zero,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: isError
                                        ? AppColors.error.withOpacity(0.7)
                                        : hasValue
                                            ? AppColors.primary.withOpacity(0.6)
                                            : (isDark ? Colors.white24 : Colors.black.withOpacity(0.1)),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: isError ? AppColors.error : AppColors.primary,
                                    width: 1.8,
                                  ),
                                ),
                              ),
                              onChanged: (v) {
                                setState(() {});
                                if (v.isNotEmpty && i < 5) {
                                  _focus[i + 1].requestFocus();
                                }
                                if (i == 5 && _digits.every((c) => c.text.isNotEmpty)) {
                                  _submit();
                                }
                              },
                            ),
                          );
                        }),
                      ).animate().fadeIn(delay: 180.ms).slideY(begin: 0.06, end: 0),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(isDark ? 0.14 : 0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.error.withOpacity(0.25)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, size: 18, color: AppColors.error),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error))),
                            ],
                          ),
                        ).animate().shake(duration: 350.ms),
                      ],
                      if (lsp.isInCooldown) ...[
                        const SizedBox(height: 8),
                        Text(
                          l10n.cooldownWait(lsp.cooldownRemaining?.inSeconds.toString() ?? '0'),
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMutedLight),
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (_biometricAvailable)
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.fingerprint, color: AppColors.primary),
                            label: Text(l10n.pinUseBiometric, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: isDark ? Colors.white24 : Colors.black.withOpacity(0.12)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
                            ),
                            onPressed: _useBiometric,
                          ),
                        ).animate().fadeIn(delay: 260.ms),
                      if (_biometricAvailable) const SizedBox(height: 12),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () async {
                                await context.read<PhoneOtpAuthProvider>().signOut();
                                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                              },
                        style: TextButton.styleFrom(
                          foregroundColor: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                        ),
                        child: Text(l10n.pinForgot, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                      ).animate().fadeIn(delay: 320.ms),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
