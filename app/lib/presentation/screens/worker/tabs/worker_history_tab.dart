import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../core/providers/transaction_provider.dart';
import '../../../../core/models/worker_model.dart';
import '../../../../core/models/transaction_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/worker_transaction_tile.dart';
import '../../../widgets/app_toast.dart';

class WorkerHistoryTab extends StatefulWidget {
  final Worker worker;
  final bool isDark;
  final VoidCallback onRefresh;

  const WorkerHistoryTab({
    super.key,
    required this.worker,
    required this.isDark,
    required this.onRefresh,
  });

  @override
  State<WorkerHistoryTab> createState() => _WorkerHistoryTabState();
}

class _WorkerHistoryTabState extends State<WorkerHistoryTab> {
  int _itemsToShow = 20;
  static const int _itemsPerLoad = 20;
  bool _approving = false;

  void _loadMore() {
    setState(() {
      _itemsToShow += _itemsPerLoad;
    });
  }

  Future<void> _approveTransaction(TransactionProvider provider, String id) async {
    setState(() => _approving = true);
    final success = await provider.approveTransaction(id);
    if (mounted) {
      setState(() => _approving = false);
      if (success) {
        AppToast.show(
          AppLocalizations.of(context)!.entryConfirmed,
          success: true,
        );
      } else {
        AppToast.show(provider.errorMessage ??
            AppLocalizations.of(context)!.failedToComplete);
      }
    }
  }

  Future<void> _approveTransfer(
      TransactionProvider provider, String transferId) async {
    setState(() => _approving = true);
    final success = await provider.approveTransfer(transferId);
    if (mounted) {
      setState(() => _approving = false);
      if (success) {
        AppToast.show(
          AppLocalizations.of(context)!.entryConfirmed,
          success: true,
        );
      } else {
        AppToast.show(provider.errorMessage ??
            AppLocalizations.of(context)!.failedToComplete);
      }
    }
  }

  Future<void> _approveAll(TransactionProvider provider) async {
    setState(() => _approving = true);
    final success = await provider.approveAllForWorker(widget.worker.id);
    if (mounted) {
      setState(() => _approving = false);
      AppToast.show(
        success
            ? AppLocalizations.of(context)!.allConfirmed
            : provider.errorMessage ??
                AppLocalizations.of(context)!.failedToComplete,
        success: success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        final allTransactions = provider.workerTransactions;

        if (allTransactions.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long,
                    size: 64,
                    color: widget.isDark
                        ? Colors.grey.shade600
                        : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.noTransactionsYet,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: widget.isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.transactionsWillAppearHere,
                    style: TextStyle(
                      color: widget.isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Paginate transactions
        final transactions = allTransactions.length > _itemsToShow
            ? allTransactions.sublist(0, _itemsToShow)
            : allTransactions;
        final hasMore = allTransactions.length > _itemsToShow;
        final remaining = allTransactions.length - _itemsToShow;

        // Group transactions by date
        final groupedTransactions = <String, List<MoneyTransaction>>{};
        for (final tx in transactions) {
          final dateKey = DateFormat('MMMM d, yyyy').format(tx.createdAt);
          groupedTransactions.putIfAbsent(dateKey, () => []).add(tx);
        }

        return RefreshIndicator(
          onRefresh: () async => widget.onRefresh(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Transaction count header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.showingTransactions(
                          '${transactions.length}', '${allTransactions.length}'),
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isDark
                            ? AppColors.textMutedDark
                            : AppColors.textMutedLight,
                      ),
                    ),
                    if (allTransactions.any((t) => !t.approved))
                      TextButton.icon(
                        onPressed:
                            _approving ? null : () => _approveAll(provider),
                        icon: _approving
                            ? const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.primary),
                              )
                            : const Icon(Icons.done_all, size: 16),
                        label: Text(
                          AppLocalizations.of(context)!.approveAll,
                          style: const TextStyle(color: AppColors.primary),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Grouped transactions
                ...groupedTransactions.entries.map((entry) {
                  final dateKey = entry.key;
                  final dayTransactions = entry.value;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          dateKey,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: widget.isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                      ...dayTransactions.map((tx) => WorkerTransactionTile(
                            transaction: tx,
                            isDark: widget.isDark,
                            onApprove: !tx.approved
                                ? (tx.isTransfer
                                    ? (tx.isTransferReceiver
                                        ? () => _approveTransfer(
                                            provider, tx.transferId!)
                                        : null)
                                    : () => _approveTransaction(
                                        provider, tx.id))
                                : null,
                          )),
                    ],
                  );
                }),

                // Load More button
                if (hasMore)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: _loadMore,
                        icon: const Icon(Icons.expand_more),
                        label: Text(AppLocalizations.of(context)!
                            .loadMore('$remaining')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(
                              color: AppColors.primary.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (allTransactions.length > _itemsPerLoad)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        AppLocalizations.of(context)!.endOfTransactions,
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isDark
                              ? AppColors.textMutedDark
                              : AppColors.textMutedLight,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 80),
              ],
            ),
          ),
        );
      },
    );
  }
}
