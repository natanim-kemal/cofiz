import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/background_pattern.dart';
import '../../../l10n/app_localizations.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _loremIpsum = """
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
""";

  void _showContentDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(content),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)?.close ?? 'Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'support@cofiz.com',
      query: 'subject=App Support',
    );
    try {
      if (await canLaunchUrl(emailLaunchUri)) {
        await launchUrl(emailLaunchUri);
      }
    } catch (_) {}
  }

  Future<void> _launchUrl(String urlString) async {
    try {
      final url = Uri.parse(urlString);
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)?.aboutCofiz ?? 'About Cofiz'),
        backgroundColor: theme.appBarTheme.backgroundColor ?? AppColors.primary,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          const BackgroundPattern(),
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Image.asset(
                  'assets/icon-bgless.png',
                  width: 100,
                  height: 100,
                ),
                const SizedBox(height: 16),
                Text(
                  'Cofiz',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.version('1.1.9'),
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 40),
                _buildSection(context, AppLocalizations.of(context)!.legal),
                _buildTile(
                  context,
                  AppLocalizations.of(context)?.termsOfService ??
                      'Terms of Service',
                  Icons.description_outlined,
                  () => _showContentDialog(
                      context,
                      AppLocalizations.of(context)?.termsOfService ??
                          'Terms of Service',
                      _loremIpsum),
                ),
                _buildTile(
                  context,
                  AppLocalizations.of(context)?.privacyPolicy ??
                      'Privacy Policy',
                  Icons.privacy_tip_outlined,
                  () => _showContentDialog(
                      context,
                      AppLocalizations.of(context)?.privacyPolicy ??
                          'Privacy Policy',
                      _loremIpsum),
                ),
                const SizedBox(height: 24),
                _buildSection(context, AppLocalizations.of(context)!.support),
                _buildTile(
                  context,
                  AppLocalizations.of(context)?.contactSupport ??
                      'Contact Support',
                  Icons.email_outlined,
                  () => _launchEmail(),
                ),
                _buildTile(
                  context,
                  AppLocalizations.of(context)?.visitWebsite ?? 'Visit Website',
                  Icons.language,
                  () => _launchUrl('https://example.com'),
                ),
                const SizedBox(height: 40),
                Text(
                  AppLocalizations.of(context)?.copyright ??
                      '© 2026 Cofiz app. All rights reserved.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white30 : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textMutedDark,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildTile(
      BuildContext context, String title, IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppColors.primary, size: 24),
        title: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }
}
