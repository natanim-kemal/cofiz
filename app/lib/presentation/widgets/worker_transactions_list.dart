import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../../core/models/transaction_model.dart';
import '../../../core/models/worker_model.dart';
import '../../core/providers/transaction_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/audit_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_formatter.dart';
import '../screens/transaction/transaction_dialog.dart';
import 'offline_indicator.dart';
import 'sync_outbox_banner.dart';
import 'app_toast.dart';

class WorkerTransactionsList extends StatefulWidget {
  final String workerId;
  final Worker worker;

  const WorkerTransactionsList({
    super.key,
    required this.workerId,
    required this.worker,
  });

  @override
  State<WorkerTransactionsList> createState() => _WorkerTransactionsListState();
}

class _WorkerTransactionsListState extends State<WorkerTransactionsList> {
  DateTime? _selectedDate;
  int _itemsToShow = 20;
  static const int _itemsPerLoad = 20;

  @override
  void initState() {
    super.initState();
    // Load transactions for this worker
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TransactionProvider>(context, listen: false)
          .loadWorkerTransactions(widget.workerId);
    });
  }

  void _reload() {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    if (_selectedDate != null) {
      provider.loadWorkerTransactionsForDay(widget.workerId, _selectedDate!);
    } else {
      provider.loadWorkerTransactions(widget.workerId);
    }
  }

  Future<void> _loadMore(TransactionProvider provider) async {
    setState(() => _itemsToShow += _itemsPerLoad);
    await provider.loadMoreWorkerTransactions(widget.workerId);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      provider.loadWorkerTransactionsForDay(widget.workerId, picked);
    }
  }

  void _clearDate() {
    setState(() => _selectedDate = null);
    _reload();
  }

  List<MoneyTransaction> _filteredTransactions(
      List<MoneyTransaction> transactions) {
    final day = _selectedDate ?? DateTime.now();
    return transactions
        .where((t) =>
            t.createdAt.year == day.year &&
            t.createdAt.month == day.month &&
            t.createdAt.day == day.day)
        .toList();
  }

  Future<void> _editTransaction(MoneyTransaction transaction) async {
    String? overrideReason;
    if (transaction.isLocked) {
      overrideReason = await _promptOverrideReason(action: 'edit');
      if (overrideReason == null || !mounted) return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => TransactionDialog(
        worker: widget.worker,
        type: transaction.type,
        existing: transaction,
        overrideReason: overrideReason,
      ),
    );
    if (result == true) {
      _reload();
    }
  }

  /// Ask the admin for a reason when editing/deleting a locked transaction.
  /// Returns null if the admin cancels.
  Future<String?> _promptOverrideReason({required String action}) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.lockedReasonTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.lockedReasonMessage(action)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l10n.reasonLabel,
                hintText: l10n.reasonHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                AppToast.show(l10n.reasonRequired);
                return;
              }
              Navigator.pop(context, text);
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _deleteTransaction(MoneyTransaction transaction) async {
    final l10n = AppLocalizations.of(context)!;

    String? overrideReason;
    if (transaction.isLocked) {
      overrideReason = await _promptOverrideReason(action: 'delete');
      if (overrideReason == null || !mounted) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteTransactionTitle),
        content: Text(l10n.deleteTransactionConfirmation(
            '${l10n.currency} ${transaction.amount.formatted}')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final transactionProvider =
        Provider.of<TransactionProvider>(context, listen: false);
    final success = transaction.isTransfer
        ? await transactionProvider.deleteTransfer(
            transaction.transferId!,
            overrideReason: overrideReason,
          )
        : await transactionProvider.deleteTransaction(
            transaction.id,
            overrideReason: overrideReason,
          );

    if (!mounted) return;
    if (success) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final auditProvider = Provider.of<AuditProvider>(context, listen: false);
      // Fire-and-forget: the audit op is queued locally, so the delete UX
      // must never block (or fail) waiting on it.
      unawaited(auditProvider.logTransactionDeleted(
        userId: authProvider.user?.uid ?? 'unknown',
        userName:
            authProvider.appUser?.displayName ?? authProvider.user?.email ?? '',
        transactionId:
            transaction.isTransfer ? transaction.transferId! : transaction.id,
        transactionType: transaction.type,
        amount: transaction.amount,
        workerName: transaction.workerName,
        wasUnconfirmed: !transaction.approved,
        reason: overrideReason,
      ));
      _reload();
      AppToast.show(l10n.transactionDeleted, success: true);
    } else {
      AppToast.show(transactionProvider.errorMessage ??
          AppLocalizations.of(context)!.failedToDeleteTransaction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<TransactionProvider>(
      builder: (context, transactionProvider, _) {
        final transactions = transactionProvider.workerTransactions;
        final filtered = _filteredTransactions(transactions);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Inline offline notice (no background) above the history.
            const OfflineIndicator(
              datasets: [],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppLocalizations.of(context)!.transactionHistory,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                // Pending/failed sync counts - right end of the header row.
                const SyncOutboxBanner(),
                if (_selectedDate != null)
                  TextButton.icon(
                    onPressed: _clearDate,
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(
                      DateFormat('MMM d, yyyy').format(_selectedDate!),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  )
                else
                  IconButton(
                    tooltip: AppLocalizations.of(context)!.filterByDate,
                    onPressed: _pickDate,
                    icon: const Icon(Icons.filter_alt),
                    color: AppColors.primary,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              _buildEmptyState()
            else ...[
              if (_selectedDate != null)
                for (final transaction in filtered)
                  _buildTransactionItem(transaction)
              else ...[
                for (final transaction in filtered.take(_itemsToShow))
                  _buildTransactionItem(transaction),
                if (filtered.length > _itemsToShow ||
                    transactionProvider.hasMoreWorkerTransactions)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed:
                            transactionProvider.isLoadingMoreWorkerTransactions
                                ? null
                                : () => _loadMore(transactionProvider),
                        icon:
                            transactionProvider.isLoadingMoreWorkerTransactions
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary),
                                  )
                                : const Icon(Icons.expand_more),
                        label: Text(AppLocalizations.of(context)!.loadMore),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.noTransactionsYet,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)!.transactionsWillAppearHere,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionItem(MoneyTransaction transaction) {
    final isPending = context
        .watch<TransactionProvider>()
        .isPending(transaction.id);
    Color typeColor;
    IconData typeIcon;
    bool isPositive = transaction.increasesBalance;
    if (transaction.isTransfer) {
      isPositive = transaction.isTransferReceiver;
    }

    switch (transaction.type.toLowerCase()) {
      case 'distribution':
        typeColor = Colors.green;
        typeIcon = Icons.add_circle;
        break;
      case 'return':
        typeColor = Colors.red;
        typeIcon = Icons.remove_circle;
        break;
      case 'purchase':
        typeColor = Colors.orange;
        typeIcon = Icons.shopping_cart;
        break;
      case 'transfer':
        typeColor = AppColors.primary;
        typeIcon = Icons.swap_horiz;
        break;
      default:
        typeColor = Colors.grey;
        typeIcon = Icons.receipt;
    }

    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final isAdmin = authProvider.isAdmin;

        return GestureDetector(
          onLongPress: isAdmin ? () => _showActionsModal(transaction) : null,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade800
                      : Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(typeIcon, color: AppColors.primary, size: 24),

                const SizedBox(width: 12),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _getTypeDisplay(context, transaction),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.color,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          _buildStatusTick(transaction, isPending),
                          if (transaction.isLocked) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              AppLocalizations.of(context)!.lockedEntry,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${DateFormat('MMM d, h:mm a').format(transaction.createdAt)}'
                        '${transaction.type == 'purchase' && transaction.notes != null && transaction.notes!.isNotEmpty ? ' · ${transaction.notes}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.textMutedDark
                              : AppColors.textMutedLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Amount
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isPositive ? '+' : '-'}${AppLocalizations.of(context)?.currency ?? 'ETB'} ${transaction.amount.formatted}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: typeColor,
                      ),
                    ),
                    if (transaction.notes != null &&
                        transaction.notes!.isNotEmpty &&
                        transaction.type != 'purchase') ...[
                      const SizedBox(height: 4),
                      Text(
                        transaction.notes!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.textMutedDark
                              : AppColors.textMutedLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (transaction.type == 'purchase' &&
                        transaction.coffeeWeight != null)
                      Text(
                        '${transaction.coffeeWeight!.formatted} ${AppLocalizations.of(context)!.kg}'
                        ' • '
                        '${AppLocalizations.of(context)?.currency ?? 'ETB'} ${(transaction.pricePerKg ?? 0).formatted}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showActionsModal(MoneyTransaction transaction) async {
    final l10n = AppLocalizations.of(context)!;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!transaction.isTransfer)
                      _buildActionChip(
                        icon: Icons.edit_outlined,
                        label: l10n.edit,
                        color: AppColors.primary,
                        value: 'edit',
                      ),
                    if (!transaction.isTransfer) const SizedBox(width: 12),
                    _buildActionChip(
                      icon: Icons.delete_outline,
                      label: l10n.delete,
                      color: AppColors.primary,
                      value: 'delete',
                    ),
                  ],
                ),
                if (transaction.receiptUrl != null &&
                    transaction.receiptUrl!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildActionChip(
                    icon: Icons.download_outlined,
                    label: l10n.receipt,
                    color: AppColors.primary,
                    value: 'receipt',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _editTransaction(transaction);
    } else if (action == 'delete') {
      await _deleteTransaction(transaction);
    } else if (action == 'receipt') {
      await _downloadReceipt(transaction);
    }
  }

  Future<void> _downloadReceipt(MoneyTransaction transaction) async {
    final l10n = AppLocalizations.of(context)!;
    final receiptUrl = transaction.receiptUrl;
    if (receiptUrl == null || receiptUrl.isEmpty) return;

    try {
      final response = await http.get(Uri.parse(receiptUrl));
      if (response.statusCode != 200) {
        if (mounted) AppToast.show(l10n.failedToDownloadReceipt);
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/receipt_${transaction.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(response.bodyBytes);

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        AppToast.show(l10n.failedToDownloadReceipt);
        return;
      }
      if (mounted) AppToast.show(l10n.receiptDownloaded, success: true);
    } catch (e) {
      if (mounted) AppToast.show(l10n.failedToDownloadReceipt);
    }
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required String value,
  }) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(context, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTypeDisplay(BuildContext context, MoneyTransaction transaction) {
    switch (transaction.type.toLowerCase()) {
      case 'distribution':
        return AppLocalizations.of(context)?.distributed ?? 'Distributed';
      case 'return':
        return AppLocalizations.of(context)?.returned ?? 'Returned';
      case 'purchase':
        return AppLocalizations.of(context)?.purchased ?? 'Purchased';
      case 'transfer':
        final fromName = transaction.fromWorkerName;
        final toName = transaction.toWorkerName;
        if (fromName != null && toName != null) {
          return transaction.isTransferSender
              ? (AppLocalizations.of(context)
                      ?.transferredTo(fromName, toName) ??
                  '$fromName transferred to $toName')
              : (AppLocalizations.of(context)
                      ?.receivedFromName(toName, fromName) ??
                  '$toName received from $fromName');
        }
        return transaction.isTransferSender
            ? (AppLocalizations.of(context)?.transferredOut ??
                'Transferred Out')
            : (AppLocalizations.of(context)?.receivedFrom ?? 'Received From');
      default:
        return transaction.type;
    }
  }

  Widget _buildStatusTick(MoneyTransaction t, bool isPending) {
    if (isPending) {
      return const Icon(Icons.access_time, size: 12, color: Colors.grey);
    }
    if (!t.approved) {
      return const Icon(Icons.done, size: 12, color: Colors.grey);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.done, size: 12, color: Colors.blue),
        Transform.translate(
          offset: const Offset(-4, 0),
          child: const Icon(Icons.done, size: 12, color: Colors.blue),
        ),
      ],
    );
  }
}
