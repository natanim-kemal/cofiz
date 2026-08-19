import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/email_verification_service.dart';
import '../../l10n/app_localizations.dart';
import 'app_toast.dart';

class VerifyEmailTile extends StatefulWidget {
  final String email;
  final bool verified;
  final Future<bool> Function() onVerify;

  const VerifyEmailTile({
    super.key,
    required this.email,
    required this.verified,
    required this.onVerify,
  });

  @override
  State<VerifyEmailTile> createState() => _VerifyEmailTileState();
}

class _VerifyEmailTileState extends State<VerifyEmailTile> {
  late bool _verified;

  @override
  void initState() {
    super.initState();
    _verified = widget.verified;
  }

  Future<void> _verify() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final ok = await widget.onVerify();
      if (!mounted) return;
      if (ok) {
        setState(() => _verified = true);
        AppToast.show(l10n.emailVerifiedSuccess, success: true);
      } else {
        AppToast.show(l10n.invalidCode);
      }
    } catch (_) {
      if (!mounted) return;
      AppToast.show(l10n.codeSendFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_verified) {
      return ListTile(
        title: Text(l10n.emailVerified),
        trailing: const Icon(Icons.verified, color: Colors.green),
      );
    }
    return ListTile(
      title: Text(l10n.verifyEmail),
      subtitle: Text(widget.email),
      trailing: ElevatedButton(onPressed: _verify, child: Text(l10n.verify)),
    );
  }
}

class VerificationDialog extends StatefulWidget {
  final String email;
  final EmailVerificationService? service;

  const VerificationDialog({super.key, required this.email, this.service});

  @override
  State<VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends State<VerificationDialog> {
  static const int _totalAttempts = 5;
  static const int _countdownSeconds = 600;

  late final EmailVerificationService _service =
      widget.service ?? EmailVerificationService();
  final List<TextEditingController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  Timer? _timer;
  int _countdown = _countdownSeconds;
  int _attempts = _totalAttempts;
  bool _locked = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 6; i++) {
      _controllers.add(TextEditingController());
      _focusNodes.add(FocusNode());
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_countdown > 0) _countdown--;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _handleChanged(int index, String value) {
    if (value.isEmpty) {
      if (index > 0) _focusNodes[index - 1].requestFocus();
      return;
    }
    if (value.length > 1) {
      final chars = value.split('');
      final fillCount = chars.length > 6 - index ? 6 - index : chars.length;
      for (var i = 0; i < fillCount; i++) {
        _controllers[index + i].text = chars[i];
      }
      final nextEmpty = index + fillCount;
      if (nextEmpty < 6) _focusNodes[nextEmpty].requestFocus();
      return;
    }
    if (index < 5) _focusNodes[index + 1].requestFocus();
  }

  Future<void> _resendCode() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _countdown = _countdownSeconds;
      _attempts = _totalAttempts;
      _locked = false;
    });
    try {
      await _service.requestCode(widget.email);
      if (!mounted) return;
      AppToast.show(l10n.codeSentToEmail);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(l10n.codeSendFailed);
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final code = _controllers.map((c) => c.text).join();
    if (code.length != 6) {
      AppToast.show(l10n.invalidCode);
      return;
    }
    setState(() => _submitting = true);
    try {
      final ok = await _service.verifyCode(code);
      if (!mounted) return;
      if (ok) {
        AppToast.show(l10n.emailVerifiedSuccess, success: true);
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _submitting = false;
          _attempts--;
          if (_attempts <= 0) {
            _attempts = 0;
            _locked = true;
          }
        });
        AppToast.show(l10n.invalidCode);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      setState(() {
        _submitting = false;
        if (msg.contains('expired') || msg.contains('too many')) {
          _locked = true;
        } else {
          _attempts--;
          if (_attempts <= 0) {
            _attempts = 0;
            _locked = true;
          }
        }
      });
      AppToast.show(msg.contains('expired')
          ? l10n.codeExpired
          : msg.contains('too many')
              ? l10n.tooManyAttempts
              : l10n.invalidCode);
    }
  }

  String _formatCountdown(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mutedColor =
        isDark ? const Color(0xFF9E9E9E) : const Color(0xFF757575);

    return AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.enterVerificationCode),
          const SizedBox(height: 4),
          Text(
            widget.email,
            style: TextStyle(fontSize: 12, color: mutedColor),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 6; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: TextField(
                    controller: _controllers[i],
                    focusNode: _focusNodes[i],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                    decoration: const InputDecoration(
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => _handleChanged(i, value),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _countdown > 0 ? null : _resendCode,
                child: Text(l10n.resendCode),
              ),
              Text(
                _formatCountdown(_countdown),
                style: TextStyle(
                  fontSize: 12,
                  color: mutedColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _locked ? l10n.tooManyAttempts : l10n.attemptsRemaining(_attempts),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: _locked ? theme.colorScheme.error : mutedColor,
            ),
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: (_submitting || _locked) ? null : _submit,
          child: Text(l10n.verify),
        ),
      ],
    );
  }
}
