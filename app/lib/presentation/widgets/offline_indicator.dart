import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/offline_cache_service.dart';
import '../../l10n/app_localizations.dart';
import '../../core/services/offline_sync_service.dart';
import 'sync_outbox_banner.dart';

/// Floating connectivity + sync-status capsule.
///
/// Rendered as a rounded, elevated card inset from the screen edges (so it
/// spans between the header's curve edges and never hides behind the camera
/// cutout), instead of the old edge-to-edge bar pinned at top:0. Composes
/// two segments:
///  - an offline row (amber) shown while [ConnectivityService] is offline,
///    including the age of the cached data being viewed;
///  - the outbox capsule ([SyncOutboxBanner]) shown whenever operations are
///    pending/failed - it intentionally survives reconnection so failures
///    remain discoverable.
class OfflineIndicator extends StatefulWidget {
  /// Datasets whose fetch time reflects the data visible on this screen.
  /// Defaults to the main transactions collection; screens built from other
  /// caches (e.g. the collector dashboard) should pass their own.
  final List<String> datasets;

  const OfflineIndicator({super.key, this.datasets = const []});

  @override
  State<OfflineIndicator> createState() => _OfflineIndicatorState();
}

class _OfflineIndicatorState extends State<OfflineIndicator> {
  final ConnectivityService _connectivity = ConnectivityService();
  final OfflineSyncService _sync = OfflineSyncService();
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _isOnline = _connectivity.isOnline;

    _connectivity.connectionStatus.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  /// Human-readable age of the locally cached data, e.g. "14:32" for the
  /// time it was last fetched today. Null when nothing was ever fetched.
  String? _cachedDataAge() {
    final datasets = widget.datasets.isNotEmpty
        ? widget.datasets
        : <String>[OfflineCacheService.dsTransactions];
    final fetchedAt = OfflineCacheService().newestFetchedAt(datasets);
    if (fetchedAt == null) return null;
    return DateFormat('HH:mm').format(fetchedAt);
  }

  @override
  Widget build(BuildContext context) {
    // SafeArea keeps the capsule clear of the status bar / camera cutout;
    // horizontal insets let it span "between" the header's curved corners.
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.4),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: _isOnline
                    ? const SizedBox.shrink()
                    : KeyedSubtree(
                        key: const ValueKey('offline-bar'),
                        child: _buildOfflineBar(context),
                      ),
              ),
              // Outbox banner self-hides when nothing is pending/failed, and
              // stays visible after reconnect so failed operations remain
              // discoverable.
              const SyncOutboxBanner(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineBar(BuildContext context) {
    final pendingCount = _sync.getPendingOperationsCount();
    final age = _cachedDataAge();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade900,
        borderRadius: BorderRadius.circular(18),
        elevation: 6,
        shadowColor: Colors.black26,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.orangeAccent,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orangeAccent.withOpacity(0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    age == null
                        ? (pendingCount > 0
                            ? AppLocalizations.of(context)!
                                .offlineSyncPending('$pendingCount')
                            : AppLocalizations.of(context)!.youAreOffline)
                        : '${AppLocalizations.of(context)!.youAreOffline}'
                            ' · $age',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.cloud_off_rounded,
                    color: Colors.orangeAccent.withOpacity(0.9), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
