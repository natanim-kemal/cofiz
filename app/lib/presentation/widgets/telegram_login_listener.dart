import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import '../../core/providers/phone_otp_auth_provider.dart';

/// Listens for incoming deep links of the form `cofiz://auth/telegram?...`
/// from the Telegram Login Widget and forwards the fields to
/// [PhoneOtpAuthProvider.completeTelegramLogin].
///
/// Mounted once at app root in `main.dart` so it lives for the app's lifetime.
class TelegramLoginListener extends StatefulWidget {
  const TelegramLoginListener({super.key, required this.child});
  final Widget child;

  @override
  State<TelegramLoginListener> createState() => _TelegramLoginListenerState();
}

class _TelegramLoginListenerState extends State<TelegramLoginListener> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  @override
  void initState() {
    super.initState();
    // Listen for subsequent deep links.
    _sub = _appLinks.uriLinkStream.listen(_onUri, onError: (_) {});
    // Also handle a deep link that launched the app.
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _onUri(uri);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onUri(Uri uri) {
    // Accept only our scheme. The Telegram widget posts to the URL we set as
    // `return_to` (cofiz://auth/telegram) with the user fields as query params.
    if (uri.scheme != 'cofiz') return;
    if (uri.host != 'auth' || uri.pathSegments.first != 'telegram') return;
    final fields = <String, String>{};
    uri.queryParameters.forEach((k, v) {
      fields[k] = v;
    });
    if (fields.isEmpty) return;
    if (!mounted) return;
    context.read<PhoneOtpAuthProvider>().completeTelegramLogin(fields: fields);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
