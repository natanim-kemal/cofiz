import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../core/providers/transaction_provider.dart';
import '../../../../../core/utils/number_formatter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/worker_model.dart';
import '../widgets/worker_stat_card.dart';
import '../widgets/worker_transaction_tile.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/custom_header.dart';
import '../../../widgets/notification_badge.dart';
import '../../notifications/notifications_screen.dart';

class WorkerHomeTab extends StatefulWidget {
  final Worker worker;
  final bool isDark;
  final VoidCallback onRefresh;
  final VoidCallback onViewHistory;

  const WorkerHomeTab({
    super.key,
    required this.worker,
    required this.isDark,
    required this.onRefresh,
    required this.onViewHistory,
  });

  @override
  State<WorkerHomeTab> createState() => _WorkerHomeTabState();
}

class _WorkerHomeTabState extends State<WorkerHomeTab> {
  bool _approving = false;

  Future<void> _approveTransaction(
      TransactionProvider provider, String id) async {
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
    return Column(
      children: [
        CustomHeader(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.welcomeBack,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.worker.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      NotificationBadge(
                        child: IconButton(
                          icon: const Icon(
                            Icons.notifications_outlined,
                            color: Colors.white,
                            size: 28,
                          ),
                          tooltip: AppLocalizations.of(context)!.notifications,
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const NotificationsScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => widget.onRefresh(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: WorkerStatCard(
                        label: AppLocalizations.of(context)!.totalDistributed,
                        value:
                            'ETB ${widget.worker.totalDistributed.formatted}',
                        icon: Icons.arrow_downward,
                        isDark: widget.isDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: WorkerStatCard(
                        label: AppLocalizations.of(context)!.totalReturned,
                        value: 'ETB ${widget.worker.totalReturned.formatted}',
                        icon: Icons.arrow_upward,
                        isDark: widget.isDark,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: WorkerStatCard(
                        label: AppLocalizations.of(context)!.coffeePurchased,
                        value:
                            'ETB ${widget.worker.totalCoffeePurchased.formatted}',
                        icon: Icons.shopping_cart,
                        isDark: widget.isDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: WorkerStatCard(
                        label: AppLocalizations.of(context)!.commissionEarned,
                        value:
                            'ETB ${widget.worker.totalCommissionEarned.formatted}',
                        icon: Icons.paid,
                        isDark: widget.isDark,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Balance Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.primary.withOpacity(0.7)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.currentBalance,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ETB ${widget.worker.currentBalance.formatted}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(
                            widget.worker.currentBalance < 500
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle,
                            color: widget.worker.currentBalance < 500
                                ? Colors.orange
                                : Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.worker.currentBalance < 500
                                ? AppLocalizations.of(context)!
                                    .lowBalanceWarning
                                : AppLocalizations.of(context)!.balanceGood,
                            style: TextStyle(
                              color: widget.worker.currentBalance < 500
                                  ? Colors.orange
                                  : Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                _buildPendingApprovals(),

                const SizedBox(height: 24),

                // Recent Transactions Preview
                _buildRecentTransactionsPreview(widget.isDark),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingApprovals() {
    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        final pending =
            provider.workerTransactions.where((t) => !t.approved).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      AppLocalizations.of(context)!.pendingApprovals,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: widget.isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                if (pending.isNotEmpty)
                  TextButton.icon(
                    onPressed: _approving ? null : () => _approveAll(provider),
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
            if (pending.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: widget.isDark
                          ? Colors.white10
                          : Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withOpacity(widget.isDark ? 0.2 : 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.noPendingApprovals,
                        style: TextStyle(
                          color: widget.isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...pending.map((tx) => WorkerTransactionTile(
                    transaction: tx,
                    isDark: widget.isDark,
                    onApprove: !tx.approved
                        ? (tx.isTransfer
                            ? (tx.isTransferReceiver
                                ? () =>
                                    _approveTransfer(provider, tx.transferId!)
                                : null)
                            : () => _approveTransaction(provider, tx.id))
                        : null,
                  )),
          ],
        );
      },
    );
  }

  Widget _buildRecentTransactionsPreview(bool isDark) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        final transactions = provider.workerTransactions.take(3).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppLocalizations.of(context)!.recentActivity,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                TextButton(
                  onPressed: widget.onViewHistory,
                  child: Text(
                    AppLocalizations.of(context)!.viewAll,
                    style: const TextStyle(color: AppColors.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (transactions.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    AppLocalizations.of(context)!.noTransactionsYet,
                    style: TextStyle(
                      color:
                          isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ),
              )
            else
              ...transactions.map((tx) =>
                  WorkerTransactionTile(transaction: tx, isDark: isDark)),
          ],
        );
      },
    );
  }
}
