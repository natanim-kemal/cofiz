import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/services/offline_cache_service.dart';
import '../../core/services/offline_sync_service.dart';
import '../../l10n/app_localizations.dart';

/// Inline outbox status: plain "N pending · M failed" white text with a
/// Retry tap action (and per-failed discard icons when failures exist).
///
/// Designed to sit at the right end of the header's date/filter row -
/// background-free, matching the header's white typography. Hidden entirely
/// when both boxes are empty; stays visible after reconnect so failures
/// remain discoverable.
class SyncOutboxBanner extends StatefulWidget {
  final VoidCallback? onRetry;
  final void Function(String opId)? onDiscard;

  const SyncOutboxBanner({super.key, this.onRetry, this.onDiscard});

  @override
  State<SyncOutboxBanner> createState() => _SyncOutboxBannerState();
}

class _SyncOutboxBannerState extends State<SyncOutboxBanner> {
  List<Listenable>? _listenables;

  @override
  void initState() {
    super.initState();
    if (Hive.isBoxOpen(OfflineCacheService.pendingBoxName) &&
        Hive.isBoxOpen(OfflineCacheService.failedBoxName)) {
      _listenables = [
        Hive.box(OfflineCacheService.pendingBoxName).listenable(),
        Hive.box(OfflineCacheService.failedBoxName).listenable(),
      ];
    }
  }

  @override
  void dispose() {
    _listenables = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_listenables == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: Listenable.merge(_listenables!),
      builder: (context, _) {
        final cache = OfflineCacheService();
        final pending = cache.getPendingOperations();
        final failed = cache.getFailedOperations();
        if (pending.isEmpty && failed.isEmpty) {
          return const SizedBox.shrink();
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: const Key('outbox_retry'),
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onRetry ?? () => OfflineSyncService().syncNow(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      failed.isEmpty
                          ? Icons.outbound_rounded
                          : Icons.error_outline_rounded,
                      size: 14,
                      color: failed.isEmpty ? Colors.white : Colors.redAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${pending.length} pending · ${failed.length} failed',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            for (final op in failed)
              InkWell(
                key: Key('discard_${op['opId']}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final opId = op['opId'] as String?;
                  if (opId == null) return;
                  if (widget.onDiscard != null) {
                    widget.onDiscard!(opId);
                  } else {
                    await cache.discardFailed(opId);
                  }
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  child: Icon(Icons.close_rounded,
                      size: 14, color: Colors.white.withOpacity(0.75)),
                ),
              ),
          ],
        );
      },
    );
  }
}
