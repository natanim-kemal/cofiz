import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/user_model.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/ping_service.dart';
import '../../core/theme/app_theme.dart';
import 'app_toast.dart';

/// Presets per role
const _collectorPresets = ['Need cash', 'Issue with record', 'Report ready'];
const _viewerPresets = ['Need clarification', 'Report looks off', 'Request summary'];

List<String> _presetsForRole(UserRole role) {
  if (role == UserRole.viewer) return _viewerPresets;
  if (role == UserRole.worker) return _collectorPresets;
  // admin or others: empty (or collector as fallback, but spec expects no presets)
  return [];
}

/// Shows the Ping Admin bottom sheet.
///
/// [role] determines which presets are shown.
/// [isOnline] and [onSend] are injectable for tests.
Future<void> showPingAdminSheet(
  BuildContext context,
  UserRole role, {
  bool Function()? isOnline,
  Future<void> Function(String note)? onSend,
  PingService? pingService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => PingAdminSheet(
      role: role,
      isOnline: isOnline,
      onSend: onSend,
      pingService: pingService,
    ),
  );
}

class PingAdminSheet extends StatefulWidget {
  final UserRole role;
  final bool Function()? isOnline;
  final Future<void> Function(String note)? onSend;
  final PingService? pingService;

  const PingAdminSheet({
    super.key,
    required this.role,
    this.isOnline,
    this.onSend,
    this.pingService,
  });

  @override
  State<PingAdminSheet> createState() => _PingAdminSheetState();
}

class _PingAdminSheetState extends State<PingAdminSheet> {
  late final TextEditingController _controller;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isOnline {
    if (widget.isOnline != null) return widget.isOnline!.call();
    return ConnectivityService().isOnline;
  }

  bool get _canSend {
    if (_sending) return false;
    if (!_isOnline) return false;
    final text = _controller.text.trim();
    if (text.isEmpty) return false;
    if (text.length > 120) return false;
    return true;
  }

  Future<void> _handleSend() async {
    if (!_canSend) return;
    final note = _controller.text.trim();
    // Offline gate
    if (!_isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are offline — connect to send ping')),
        );
      }
      AppToast.show('You are offline — connect to send ping');
      return;
    }

    setState(() => _sending = true);
    try {
      if (widget.onSend != null) {
        await widget.onSend!.call(note);
      } else {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final senderId = auth.user?.uid ?? auth.appUser?.uid ?? '';
        final senderName = auth.appUser?.displayName ?? auth.getUserDisplayName() ?? 'Unknown';
        // Use role from widget, but senderRole from actual auth if available
        final senderRole = widget.role;
        if (senderId.isEmpty) {
          throw StateError('Not authenticated');
        }
        final svc = widget.pingService ?? PingService();
        await svc.pingAdmin(
          note: note,
          senderId: senderId,
          senderName: senderName,
          senderRole: senderRole,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.show('Ping sent to admins', success: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ping sent to admins')),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      final msg = e.message.contains('cooldown')
          ? 'Please wait 2 minutes before pinging again'
          : e.message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      AppToast.show(msg);
    } on ArgumentError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      // Try ping fallback for offline detection
      if (!_isOnline) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are offline — connect to send ping')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send ping: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presets = _presetsForRole(widget.role);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textLen = _controller.text.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ping Admin',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.role == UserRole.viewer
                    ? 'Send a quick note to admins'
                    : 'Send a quick note to admins',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                ),
              ),
              const SizedBox(height: 16),
              if (presets.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presets
                      .map(
                        (p) => ChoiceChip(
                          label: Text(p),
                          selected: _controller.text == p,
                          onSelected: (_) {
                            _controller.text = p;
                            _controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: p.length),
                            );
                          },
                        ),
                      )
                      .toList(),
                ),
              if (presets.isNotEmpty) const SizedBox(height: 16),
              TextField(
                controller: _controller,
                maxLength: 120,
                maxLines: 4,
                minLines: 3,
                decoration: InputDecoration(
                  hintText: 'Write your message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  counterText: '$textLen/120',
                ),
              ),
              const SizedBox(height: 8),
              if (!_isOnline)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, size: 16, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      Text(
                        'You are offline — connect to send',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.redAccent.shade200,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSend ? _handleSend : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _sending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Send', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Small button used on Worker dashboard below Balance Card.
/// Visible only for collectors (UserRole.worker).
class PingAdminButton extends StatelessWidget {
  const PingAdminButton({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (auth.userRole != UserRole.worker) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => showPingAdminSheet(context, UserRole.worker),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('Ping Admin'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary.withOpacity(0.6)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}
