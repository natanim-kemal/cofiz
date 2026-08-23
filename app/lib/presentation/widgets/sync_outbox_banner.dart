import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/services/offline_cache_service.dart';
import '../../core/services/offline_sync_service.dart';
import '../../l10n/app_localizations.dart';

/// Outbox banner showing queued/failed sync operation counts.
///
/// Rendered as a floating rounded capsule (horizontally inset so it spans
/// between the header's curve edges rather than edge-to-edge under the
/// camera cutout). Visible whenever the pending or failed operation boxes
/// are non-empty - regardless of connectivity, so failures stay
/// discoverable after reconnect. Offers a Retry action
/// ([OfflineSyncService.syncNow]) and a per-failed-operation Discard action
/// ([OfflineCacheService.discardFailed]). Override either behaviour via
/// [onRetry] / [onDiscard] (mainly for tests).
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
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge(_listenables!),
      builder: (context, _) {
        final cache = OfflineCacheService();
        final pending = cache.getPendingOperations();
        final failed = cache.getFailedOperations();
        if (pending.isEmpty && failed.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Material(
            color: theme.brightness == Brightness.dark
                ? Colors.grey.shade900
                : Colors.grey.shade900,
            borderRadius: BorderRadius.circular(18),
            elevation: 6,
            shadowColor: Colors.black26,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.onRetry ?? () => OfflineSyncService().syncNow(),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                child: Row(
                  children: [
                    // Status ring: amber while pending, red once anything
                    // has permanently failed.
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            failed.isEmpty ? Colors.amberAccent : Colors.redAccent,
                        boxShadow: [
                          BoxShadow(
                            color: (failed.isEmpty
                                    ? Colors.amberAccent
                                    : Colors.redAccent)
                                .withOpacity(0.5),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${pending.length} pending · ${failed.length} failed',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      key: const Key('outbox_retry'),
                      onPressed: widget.onRetry ??
                          () => OfflineSyncService().syncNow(),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withOpacity(0.12),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(AppLocalizations.of(context)?.retry ?? 'Retry'),
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
                                icon: const Icon(Icons.close_rounded, size: 18),
                                color: Colors.white70,
                                onPressed: () async {
                                  final opId = op['opId'] as String?;
                                  if (opId == null) return;
                                  if (widget.onDiscard != null) {
                                    widget.onDiscard!(opId);
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
              ),
            ),
          ),
        );
      },
    );
  }
}
