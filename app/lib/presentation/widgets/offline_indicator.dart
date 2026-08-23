import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/offline_cache_service.dart';
import '../../l10n/app_localizations.dart';
import '../../core/services/offline_sync_service.dart';
import 'sync_outbox_banner.dart';

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_isOnline) _buildOfflineBar(context),
        // Outbox banner self-hides when nothing is pending/failed, and stays
        // visible after reconnect so failed operations remain discoverable.
        const SyncOutboxBanner(),
      ],
    );
  }

  Widget _buildOfflineBar(BuildContext context) {
    final pendingCount = _sync.getPendingOperationsCount();
    final age = _cachedDataAge();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.orange.shade700,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Flexible(
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
                fontSize: 12,
                fontWeight: FontWeight.w600,
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
