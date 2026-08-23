import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/offline_cache_service.dart';
import '../../l10n/app_localizations.dart';
import '../../core/services/offline_sync_service.dart';
import 'sync_outbox_banner.dart';

/// Warm-orange-to-red tone used for the inline offline notice - sits
/// between the app's warm orange ([AppColors.primary] family) and red.
const Color kOfflineTextColor = Color(0xFFE0512C);

/// Inline offline notice shown directly beneath the screen's title header
/// (between the warm-orange header and the first card section).
///
/// Deliberately background-free: just the cloud icon and a short message in
/// the orange/red accent tone. Renders nothing while online.
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
    if (_isOnline) return const SizedBox.shrink();
    final pendingCount = _sync.getPendingOperationsCount();
    final age = _cachedDataAge();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              color: kOfflineTextColor.withOpacity(0.9), size: 16),
          const SizedBox(width: 6),
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
                color: kOfflineTextColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Backwards-compatible alias: screens that previously stacked the old
/// floating banner can drop [SyncOutboxBanner] into any Row; it renders as
/// plain white text ("N pending · M failed") with retry/discard actions.
class OfflineOutboxInline extends StatelessWidget {
  const OfflineOutboxInline({super.key});
  @override
  Widget build(BuildContext context) => const SyncOutboxBanner();
}
