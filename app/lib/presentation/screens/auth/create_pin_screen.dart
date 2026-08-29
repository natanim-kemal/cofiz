import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/lock_state_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/background_pattern.dart';
import '../../widgets/app_toast.dart';

class CreatePinScreen extends StatefulWidget {
  const CreatePinScreen({super.key});
  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  final _first = List.generate(6, (_) => TextEditingController());
  final _confirm = List.generate(6, (_) => TextEditingController());
  final _firstFocus = List.generate(6, (_) => FocusNode());
  final _confirmFocus = List.generate(6, (_) => FocusNode());
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _first) c.dispose();
    for (final c in _confirm) c.dispose();
    for (final f in _firstFocus) f.dispose();
    for (final f in _confirmFocus) f.dispose();
    super.dispose();
  }

  String _collect(List<TextEditingController> cs) => cs.map((c) => c.text).join();

  Future<void> _submit() async {
    final a = _collect(_first);
    final b = _collect(_confirm);
    final l10n = AppLocalizations.of(context)!;
    if (a.length != 6 || b.length != 6) {
      setState(() => _error = l10n.pinMismatch);
      return;
    }
    if (a != b) {
      setState(() => _error = l10n.pinMismatch);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final lsp = context.read<LockStateProvider>();
    try {
      await lsp.pinService.setPin(a);
      // Mark initialized
      await lsp.initialize();
      if (mounted) {
        AppToast.show(l10n.pinSaved, success: true);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Invalid argument(s): ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _pinRow(List<TextEditingController> cs, List<FocusNode> fs, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (i) {
        final hasValue = cs[i].text.isNotEmpty;
        return SizedBox(
          width: 46,
          height: 56,
          child: TextField(
            key: Key(i < 3 ? 'pinDigit$i' : 'pinConfirmDigit${i - 3}'),
            controller: cs[i],
            focusNode: fs[i],
            maxLength: 1,
            obscureText: true,
            obscuringCharacter: '●',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
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
                  color: hasValue
                      ? AppColors.primary.withOpacity(0.6)
                      : (isDark ? Colors.white24 : Colors.black.withOpacity(0.1)),
                  width: 1.4,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppColors.error.withOpacity(0.8)),
              ),
            ),
            onChanged: (v) {
              setState(() {});
              if (v.isNotEmpty && i < 5) {
                fs[i + 1].requestFocus();
              } else if (v.isNotEmpty && i == 5) {
                // auto-move to first confirm field if on first row
                if (cs == _first) {
                  _confirmFocus[0].requestFocus();
                }
              }
              if (v.isEmpty && i > 0) {
                // backspace handling via onChanged not perfect, but ok
              }
              // auto-submit when both rows full
              if (_collect(_first).length == 6 && _collect(_confirm).length == 6) {
                // small delay for UX
                Future.delayed(const Duration(milliseconds: 120), _submit);
              }
            },
          ),
        );
      }),
    );
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
                    const SizedBox(height: 60),
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                        ),
                        child: const Icon(Icons.lock_rounded, size: 36, color: AppColors.primary),
                      ),
                    ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.9, 0.9)),
                    const SizedBox(height: 20),
                    Text(
                      l10n.createPinTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0),
                    const SizedBox(height: 8),
                    Text(
                      l10n.pinLockSubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                      ),
                    ).animate().fadeIn(delay: 150.ms),
                    const SizedBox(height: 36),
                    Text(l10n.createPinTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                            ))
                        .animate()
                        .fadeIn(delay: 200.ms),
                    const SizedBox(height: 10),
                    _pinRow(_first, _firstFocus, isDark).animate().fadeIn(delay: 220.ms).slideY(begin: 0.05, end: 0),
                    const SizedBox(height: 24),
                    Text(l10n.confirmPinTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                            ))
                        .animate()
                        .fadeIn(delay: 280.ms),
                    const SizedBox(height: 10),
                    _pinRow(_confirm, _confirmFocus, isDark).animate().fadeIn(delay: 300.ms).slideY(begin: 0.05, end: 0),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(isDark ? 0.15 : 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.error.withOpacity(0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, size: 18, color: AppColors.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error)),
                            ),
                          ],
                        ),
                      ).animate().shake(duration: 400.ms),
                    ],
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        key: const Key('pinContinue'),
                        onPressed: _saving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text(l10n.confirm, style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.1, end: 0),
                    const SizedBox(height: 40),
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
