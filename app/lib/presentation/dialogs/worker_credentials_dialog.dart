import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/app_toast.dart';

class WorkerCredentialsDialog extends StatelessWidget {
  final String workerName;
  final String email;
  final String password;
  final String? phone;

  const WorkerCredentialsDialog({
    super.key,
    required this.workerName,
    required this.email,
    required this.password,
    this.phone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(AppLocalizations.of(context)!.workerAccountCreated),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.loginCredentialsFor(workerName),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 16),
            _buildCredentialField(
                context, AppLocalizations.of(context)!.email, email),
            const SizedBox(height: 12),
            _buildCredentialField(
                context, AppLocalizations.of(context)!.password, password),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)!.sendCredentialsToWorker,
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (phone != null)
          TextButton.icon(
            onPressed: () => _sendViaSMS(context),
            icon: const Icon(Icons.sms, color: AppColors.primary),
            label: Text(AppLocalizations.of(context)!.sendSms),
          ),
        TextButton.icon(
          onPressed: () => _copyToClipboard(context),
          icon: const Icon(Icons.copy, color: AppColors.primary),
          label: Text(AppLocalizations.of(context)!.copy),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.done),
        ),
      ],
    );
  }

  Widget _buildCredentialField(
      BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
        ],
      ),
    );
  }

  void _sendViaSMS(BuildContext context) {
    if (phone == null) return;

    final l10n = AppLocalizations.of(context)!;
    final message = Uri.encodeComponent(
      '${l10n.welcomeToCofiz}\n\n'
      '${l10n.email}: $email\n'
      '${l10n.password}: $password\n\n'
      '${l10n.downloadAppMessage}',
    );

    final smsUri = 'sms:$phone?body=$message';

    launchUrl(Uri.parse(smsUri)).then((success) {
      if (!success) {
        AppToast.show(AppLocalizations.of(context)!.couldNotOpenSms);
      }
    });
  }

  void _copyToClipboard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final credentials = '''
${l10n.loginCredentialsTitle}

${l10n.workerName}: $workerName
${l10n.email}: $email
${l10n.password}: $password
''';

    Clipboard.setData(ClipboardData(text: credentials));
    AppToast.show(AppLocalizations.of(context)!.credentialsCopied);
  }
}
