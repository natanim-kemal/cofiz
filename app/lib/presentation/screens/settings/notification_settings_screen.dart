import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/email_verification_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/verification_dialog.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.notifications,
            style: const TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSwitchTile(
                context,
                title: AppLocalizations.of(context)!.emailNotifications,
                subtitle: AppLocalizations.of(context)!.receiveUpdatesViaEmail,
                value: settings.emailNotifications,
                onChanged: (val) => settings.toggleEmailNotifications(val),
              ),
              if (settings.emailNotifications)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Consumer<AuthProvider>(
                    builder: (ctx, auth, _) => VerifyEmailTile(
                      email: auth.appUser?.email ?? '',
                      verified: auth.appUser?.emailVerified ?? false,
                      onVerify: () => _startVerification(ctx),
                    ),
                  ),
                ),
              _buildSwitchTile(
                context,
                title: AppLocalizations.of(context)!.pushNotifications,
                subtitle: AppLocalizations.of(context)!.receiveInstantAlerts,
                value: settings.pushNotifications,
                onChanged: (val) => settings.togglePushNotifications(val),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
        ),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.primary,
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.textTheme.bodyLarge?.color,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
          ),
        ),
      ),
    );
  }

  Future<bool> _startVerification(BuildContext context) async {
    final email = context.read<AuthProvider>().appUser?.email;
    if (email == null || email.isEmpty) return false;
    try {
      await EmailVerificationService().requestCode(email);
      if (!context.mounted) return false;
      AppToast.show(AppLocalizations.of(context)!.codeSentToEmail);
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => VerificationDialog(email: email),
      );
      return ok ?? false;
    } catch (_) {
      if (!context.mounted) return false;
      AppToast.show(AppLocalizations.of(context)!.codeSendFailed);
      return false;
    }
  }
}
