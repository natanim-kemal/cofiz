import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/lock_state_provider.dart';
import '../../../core/providers/phone_otp_auth_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../auth/create_pin_screen.dart';
import '../../widgets/app_toast.dart';

class PinLockSettingsScreen extends StatefulWidget {
  const PinLockSettingsScreen({super.key});
  @override
  State<PinLockSettingsScreen> createState() => _PinLockSettingsScreenState();
}

class _PinLockSettingsScreenState extends State<PinLockSettingsScreen> {
  Future<void> _confirmRemove(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.confirmRemovePin),
        content: Text(l10n.confirmRemovePinBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.removePin),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<LockStateProvider>().reset();
      AppToast.show(l10n.pinRemoved, success: true);
      setState(() {});
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
      appBar: AppBar(
        title: Text(l10n.pinLock),
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: FutureBuilder<bool>(
        future: lsp.pinService.hasPin(),
        builder: (context, snap) {
          final hasPin = snap.data ?? false;
          final loading = snap.connectionState == ConnectionState.waiting;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Header card matching app's warm-orange design
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.security_rounded, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.pinLock, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(l10n.pinLockSubtitle,
                              style: theme.textTheme.bodySmall?.copyWith(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0),
              const SizedBox(height: 16),
              if (loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppColors.primary))),
              if (!loading) ...[
                _Tile(
                  icon: Icons.lock_outline_rounded,
                  title: l10n.setPin,
                  subtitle: hasPin ? 'PIN is set' : l10n.pinLockSubtitle,
                  enabled: !hasPin,
                  onTap: !hasPin
                      ? () async {
                          final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CreatePinScreen()));
                          if (ok == true && context.mounted) setState(() {});
                        }
                      : null,
                ),
                const SizedBox(height: 10),
                _Tile(
                  icon: Icons.edit_outlined,
                  title: l10n.changePin,
                  subtitle: 'Requires current PIN',
                  enabled: hasPin,
                  onTap: hasPin
                      ? () async {
                          // Reuse create screen but require old pin first
                          final oldOk = await _promptCurrentPin(context);
                          if (oldOk == null) return;
                          if (context.mounted) {
                            final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CreatePinScreen()));
                            if (ok == true && context.mounted) setState(() {});
                          }
                        }
                      : null,
                ),
                const SizedBox(height: 10),
                _Tile(
                  icon: Icons.delete_outline_rounded,
                  title: l10n.removePin,
                  subtitle: 'Remove PIN protection',
                  enabled: hasPin,
                  iconColor: AppColors.error,
                  onTap: hasPin ? () => _confirmRemove(context) : null,
                ),
                const Divider(height: 28),
                _Tile(
                  icon: Icons.lock_clock_rounded,
                  title: l10n.lockNow,
                  subtitle: l10n.lockAfter2Min,
                  onTap: () {
                    context.read<LockStateProvider>().lock();
                    AppToast.show('Locked', success: true);
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(isDark ? 0.12 : 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.18)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l10n.lockAfter2Min, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.primary))),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<String?> _promptCurrentPin(BuildContext context) async {
    final ctrl = List.generate(6, (_) => TextEditingController());
    final focus = List.generate(6, (_) => FocusNode());
    String? error;
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSt) {
          Future<void> submit() async {
            final pin = ctrl.map((c) => c.text).join();
            if (pin.length != 6) return;
            final ok = await context.read<LockStateProvider>().pinService.verifyPin(pin);
            if (ok) {
              Navigator.pop(ctx, pin);
            } else {
              setSt(() => error = AppLocalizations.of(context)!.pinIncorrect);
            }
          }

          return AlertDialog(
            title: const Text('Enter current PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (i) {
                    return SizedBox(
                      width: 40,
                      child: TextField(
                        controller: ctrl[i],
                        focusNode: focus[i],
                        maxLength: 1,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(counterText: ''),
                        onChanged: (v) {
                          if (v.isNotEmpty && i < 5) focus[i + 1].requestFocus();
                          if (i == 5 && ctrl.every((c) => c.text.isNotEmpty)) submit();
                        },
                      ),
                    );
                  }),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                onPressed: submit,
                child: const Text('Confirm'),
              ),
            ],
          );
        });
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;
  final Color? iconColor;
  const _Tile({required this.icon, required this.title, required this.subtitle, this.enabled = true, this.onTap, this.iconColor});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (iconColor ?? AppColors.primary).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: iconColor ?? AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.black26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
