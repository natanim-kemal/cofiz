import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/services/offline_cache_service.dart';
import '../../core/services/offline_sync_service.dart';

/// Outbox banner showing queued/failed sync operation counts.
///
/// Visible whenever the pending or failed operation boxes are non-empty
/// (regardless of connectivity, so failures stay discoverable after
/// reconnect). Offers a Retry action ([OfflineSyncService.syncNow]) and a
/// per-failed-operation Discard action
/// ([OfflineCacheService.discardFailed]). Override either behaviour via
/// [onRetry] / [onDiscard] (mainly for tests).
class SyncOutboxBanner extends StatelessWidget {
  final VoidCallback? onRetry;
  final void Function(String opId)? onDiscard;

  const SyncOutboxBanner({super.key, this.onRetry, this.onDiscard});

  @override
  Widget build(BuildContext context) {
    final cache = OfflineCacheService();
    if (!Hive.isBoxOpen('pending_operations') ||
        !Hive.isBoxOpen('failed_operations')) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: Listenable.merge([
        Hive.box('pending_operations').listenable(),
        Hive.box('failed_operations').listenable(),
      ]),
      builder: (context, _) {
        final pending = cache.getPendingOperations();
        final failed = cache.getFailedOperations();
        if (pending.isEmpty && failed.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          color: Colors.deepOrange.shade700,
          child: Row(
            children: [
              const Icon(Icons.outbox, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${pending.length} pending · ${failed.length} failed',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                key: const Key('outbox_retry'),
                onPressed: onRetry ?? () => OfflineSyncService().syncNow(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Retry'),
              ),
              if (failed.isNotEmpty)
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final op in failed)
                        IconButton(
                          key: Key('discard_${op['opId']}'),
                          tooltip: 'Discard',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: Colors.white,
                          onPressed: () async {
                            final opId = op['opId'] as String?;
                            if (opId == null) return;
                            if (onDiscard != null) {
                              onDiscard!(opId);
                            } else {
                              await cache.discardFailed(opId);
                            }
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
