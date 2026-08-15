import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/models/transaction_model.dart';

class WorkerTransactionTile extends StatelessWidget {
  final MoneyTransaction transaction;
  final bool isDark;
  final VoidCallback? onApprove;

  const WorkerTransactionTile({
    super.key,
    required this.transaction,
    required this.isDark,
    this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String prefix;

    switch (transaction.type) {
      case 'distribution':
        icon = Icons.arrow_downward;
        color = Colors.orange;
        prefix = '+';
        break;
      case 'return':
        icon = Icons.arrow_upward;
        color = Colors.green;
        prefix = '-';
        break;
      case 'purchase':
        icon = Icons.local_cafe;
        color = Colors.brown;
        prefix = '-';
        break;
      case 'transfer':
        icon = Icons.swap_horiz;
        color = const Color(0xFFF0A04B);
        prefix = transaction.isTransferSender ? '-' : '+';
        break;
      default:
        icon = Icons.swap_horiz;
        color = Colors.grey;
        prefix = '';
    }

    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _getTransactionTitle(context, transaction.type),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (!transaction.approved) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.pending,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.amber,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    // Show coffee type badge for purchases
                    if (transaction.type == 'purchase' &&
                        transaction.coffeeType != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.brown.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          transaction.coffeeType!
                                  .substring(0, 1)
                                  .toUpperCase() +
                              transaction.coffeeType!.substring(1),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.brown,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      DateFormat('h:mm a').format(transaction.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    // Show commission for purchases
                    if (transaction.type == 'purchase' &&
                        transaction.commissionAmount != null &&
                        transaction.commissionAmount! > 0) ...[
                      Text(
                        ' • ',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      Icon(Icons.paid, size: 12, color: Colors.teal),
                      const SizedBox(width: 2),
                      Text(
                        '${AppLocalizations.of(context)?.currency ?? 'ETB'} ${transaction.commissionAmount!.formatted}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                if (transaction.notes != null && transaction.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      transaction.notes!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$prefix ${AppLocalizations.of(context)?.currency ?? 'ETB'} ${transaction.amount.formatted}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              // Show weight and per-kilo price for purchases
              if (transaction.type == 'purchase' &&
                  transaction.coffeeWeight != null)
                Text(
                  '${transaction.coffeeWeight!.formatted} ${AppLocalizations.of(context)!.kg}'
                  ' • '
                  '${AppLocalizations.of(context)?.currency ?? 'ETB'} ${(transaction.pricePerKg ?? 0).formatted}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              if (!transaction.approved && onApprove != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: onApprove,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.confirm,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _getTransactionTitle(BuildContext context, String type) {
    switch (type) {
      case 'distribution':
        return AppLocalizations.of(context)?.moneyReceived ?? 'Money Received';
      case 'return':
        return AppLocalizations.of(context)?.moneyReturnedTitle ??
            'Money Returned';
      case 'purchase':
        return AppLocalizations.of(context)?.coffeePurchaseTitle ??
            'Coffee Purchase';
      case 'transfer':
        return transaction.isTransferSender
            ? (AppLocalizations.of(context)?.transferredOut ??
                'Transferred Out')
            : (AppLocalizations.of(context)?.receivedFrom ??
                'Received From');
      default:
        return AppLocalizations.of(context)?.transaction ?? 'Transaction';
    }
  }
}
