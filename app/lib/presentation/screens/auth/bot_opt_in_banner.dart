import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cofiz/l10n/app_localizations.dart';

class BotOptInBanner extends StatelessWidget {
  const BotOptInBanner({super.key, required this.deepLink, required this.providerLabel});
  final String deepLink;
  final String providerLabel;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Material(
      color: const Color(0xFFFFF1E2),
      child: ListTile(
        leading: const Icon(Icons.telegram),
        title: Text(t.botOptInBannerTitle),
        subtitle: Text(t.botOptInBannerBody),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => launchUrl(Uri.parse(deepLink), mode: LaunchMode.externalApplication),
      ),
    );
  }
}
