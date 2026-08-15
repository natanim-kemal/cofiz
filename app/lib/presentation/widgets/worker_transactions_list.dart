import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/models/transaction_model.dart';
import '../../../core/models/worker_model.dart';
import '../../core/providers/transaction_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_formatter.dart';
import '../screens/transaction/transaction_dialog.dart';
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
    Provider.of<TransactionProvider>(context, listen: false)
        .loadWorkerTransactions(widget.workerId);
  }

  Future<void> _editTransaction(MoneyTransaction transaction) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => TransactionDialog(
        worker: widget.worker,
        type: transaction.type,
        existing: transaction,
      ),
    );
    if (result == true) {
      _reload();
    }
  }

  Future<void> _deleteTransaction(MoneyTransaction transaction) async {
    final l10n = AppLocalizations.of(context)!;
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
            child: Text(l10n.delete,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final transactionProvider =
        Provider.of<TransactionProvider>(context, listen: false);
    final success =
        await transactionProvider.deleteTransaction(transaction.id);

    if (!mounted) return;
    if (success) {
      _reload();
      AppToast.show(l10n.transactionDeleted, success: true);
    } else {
      AppToast.show(transactionProvider.errorMessage ??
          AppLocalizations.of(context)!.failedToDeleteTransaction);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, transactionProvider, _) {
        final transactions = transactionProvider.workerTransactions;

        if (transactions.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: transactions.length > 5 ? 5 : transactions.length,
          itemBuilder: (context, index) {
            final transaction = transactions[index];
            return _buildTransactionItem(transaction);
          },
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
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
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
    Color typeColor;
    IconData typeIcon;
    bool isPositive = transaction.increasesBalance;

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
      default:
        typeColor = Colors.grey;
        typeIcon = Icons.receipt;
    }

    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final isAdmin = authProvider.isAdmin;

        return GestureDetector(
          onLongPress: isAdmin
              ? () => _showActionsModal(transaction)
              : null,
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
                Icon(typeIcon, color: typeColor, size: 24),

                const SizedBox(width: 12),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getTypeDisplay(context, transaction.type),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM d, yyyy • h:mm a')
                            .format(transaction.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.textMutedDark
                              : AppColors.textMutedLight,
                        ),
                      ),
                      if (transaction.notes != null &&
                          transaction.notes!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          transaction.notes!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.textMutedDark
                                : AppColors.textMutedLight,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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
                    if (transaction.type == 'purchase' &&
                        transaction.coffeeWeight != null)
                      Text(
                        '${transaction.coffeeWeight!.formatted} ${AppLocalizations.of(context)!.kg}'
                        ' • '
                        '${AppLocalizations.of(context)?.currency ?? 'ETB'} ${(transaction.pricePerKg ?? 0).formatted}',
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              Theme.of(context).brightness == Brightness.dark
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionChip(
                  icon: Icons.edit_outlined,
                  label: l10n.edit,
                  color: const Color(0xFFF0A04B),
                  value: 'edit',
                ),
                const SizedBox(width: 12),
                _buildActionChip(
                  icon: Icons.delete_outline,
                  label: l10n.delete,
                  color: const Color(0xFFF0A04B),
                  value: 'delete',
                ),
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

  String _getTypeDisplay(BuildContext context, String type) {
    switch (type.toLowerCase()) {
      case 'distribution':
        return AppLocalizations.of(context)?.distributed ?? 'Distributed';
      case 'return':
        return AppLocalizations.of(context)?.returned ?? 'Returned';
      case 'purchase':
        return AppLocalizations.of(context)?.purchased ?? 'Purchased';
      default:
        return type;
    }
  }
}
