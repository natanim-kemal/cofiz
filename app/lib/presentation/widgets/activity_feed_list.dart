import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/expense_record_model.dart';
import '../../core/models/income_record_model.dart';
import '../../core/models/transaction_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/number_formatter.dart';
import '../screens/expense/expenses_screen.dart';
import '../screens/income/company_income_screen.dart';
import '../screens/worker_detail/worker_detail_screen.dart';
import 'transfer_pair_card.dart';
import '../../l10n/app_localizations.dart';

enum FeedFilter { none, in_, out_ }

enum _FeedKind { transaction, income, expense }

enum _FeedDirection { in_, out_, neutral }

class _FeedItem {
  final DateTime createdAt;
  final _FeedKind kind;
  final Object payload;
  const _FeedItem(this.createdAt, this.kind, this.payload);
}

class ActivityFeedList extends StatelessWidget {
  final List<MoneyTransaction> transactions;
  final List<IncomeRecord> incomeRecords;
  final List<ExpenseRecord> expenseRecords;
  final int limit;
  final VoidCallback? onViewAll;
  final String? emptyText;
  final FeedFilter filter;

  const ActivityFeedList({
    super.key,
    required this.transactions,
    required this.incomeRecords,
    required this.expenseRecords,
    this.limit = 8,
    this.onViewAll,
    this.emptyText,
    this.filter = FeedFilter.none,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    final allEntries = <_FeedItem>[
      for (final t in transactions)
        _FeedItem(t.createdAt, _FeedKind.transaction, t),
      for (final r in incomeRecords)
        _FeedItem(r.createdAt, _FeedKind.income, r),
      for (final e in expenseRecords)
        _FeedItem(e.createdAt, _FeedKind.expense, e),
    ];

    final entries = switch (filter) {
      FeedFilter.in_ =>
        allEntries.where((e) => _directionOf(e) == _FeedDirection.in_).toList(),
      FeedFilter.out_ => allEntries
          .where((e) => _directionOf(e) == _FeedDirection.out_)
          .toList(),
      FeedFilter.none => allEntries,
    }
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final shown = _takeWithPairs(entries, limit);

    if (shown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                emptyText ?? l10n?.noTransactionsYet ?? 'No transactions yet',
                style: TextStyle(
                    color:
                        isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final children = <Widget>[];
    var i = 0;
    while (i < shown.length) {
      if (i + 1 < shown.length && _isTransferPair(shown[i], shown[i + 1])) {
        children.add(_buildLinkedPair(context, shown[i], shown[i + 1]));
        i += 2;
      } else {
        children.add(_buildRow(context, shown[i]));
        i += 1;
      }
    }
    if (onViewAll != null) {
      children.add(
        TextButton(
          onPressed: onViewAll,
          child: Text(l10n?.viewAll ?? 'View All'),
        ),
      );
    }

    return Column(children: children);
  }

  Widget _buildLinkedPair(BuildContext context, _FeedItem a, _FeedItem b) {
    return TransferPairCard<_FeedItem>(
      first: a,
      second: b,
      buildRow: (item,
              {double bottomMargin = 12, VoidCallback? onTapOverride}) =>
          _buildRow(context, item,
              bottomMargin: bottomMargin, onTapOverride: onTapOverride),
    );
  }

  List<_FeedItem> _takeWithPairs(List<_FeedItem> entries, int limit) {
    final chosen = <_FeedItem>[];
    for (var i = 0; i < entries.length && chosen.length < limit; i++) {
      chosen.add(entries[i]);
      if (chosen.length >= limit) break;
      if (i + 1 < entries.length &&
          _isTransferPair(entries[i], entries[i + 1])) {
        chosen.add(entries[i + 1]);
        i++;
      }
    }
    return chosen;
  }

  bool _isTransferPair(_FeedItem a, _FeedItem b) {
    if (a.kind != _FeedKind.transaction || b.kind != _FeedKind.transaction) {
      return false;
    }
    final ta = a.payload as MoneyTransaction;
    final tb = b.payload as MoneyTransaction;
    return ta.isTransfer &&
        tb.isTransfer &&
        ta.transferId != null &&
        ta.transferId == tb.transferId;
  }

  _FeedDirection _directionOf(_FeedItem item) {
    switch (item.kind) {
      case _FeedKind.income:
        return _FeedDirection.in_;
      case _FeedKind.expense:
        return _FeedDirection.out_;
      case _FeedKind.transaction:
        final t = item.payload as MoneyTransaction;
        if (t.isTransfer) return _FeedDirection.neutral;
        if (t.type.toLowerCase() == 'purchase') {
          return _FeedDirection.neutral;
        }
        return t.increasesBalance ? _FeedDirection.out_ : _FeedDirection.in_;
    }
  }

  Widget _buildRow(BuildContext context, _FeedItem item,
      {double bottomMargin = 12, VoidCallback? onTapOverride}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor =
        isDark ? AppColors.textMutedDark : AppColors.textMutedLight;

    IconData icon;
    String title;
    String subtitle;
    String amount;
    String? weightLabel;
    Color amountColor;
    VoidCallback onTap;

    switch (item.kind) {
      case _FeedKind.transaction:
        final t = item.payload as MoneyTransaction;
        switch (t.type.toLowerCase()) {
          case 'distribution':
            icon = Icons.arrow_upward;
            title = l10n?.distributed ?? 'Distributed';
            amountColor = AppColors.error;
            amount = '-${l10n?.currency ?? 'ETB'} ${t.amount.formatted}';
            break;
          case 'return':
            icon = Icons.arrow_downward;
            title = l10n?.returned ?? 'Returned';
            amountColor = AppColors.success;
            amount = '+${l10n?.currency ?? 'ETB'} ${t.amount.formatted}';
            break;
          case 'transfer':
            icon = Icons.swap_horiz;
            final fromName = t.fromWorkerName;
            final toName = t.toWorkerName;
            title = fromName != null && toName != null
                ? (t.isTransferSender
                    ? l10n?.transferredTo(fromName, toName) ??
                        '$fromName transferred to $toName'
                    : l10n?.receivedFromName(toName, fromName) ??
                        '$toName received from $fromName')
                : (t.isTransferSender
                    ? l10n?.transferredOut ?? 'Transferred Out'
                    : l10n?.receivedFrom ?? 'Received From');
            amountColor = AppColors.primary;
            amount = '${l10n?.currency ?? 'ETB'} ${t.amount.formatted}';
            break;
          default:
            icon = Icons.shopping_cart;
            title = l10n?.purchased ?? 'Purchased';
            amountColor = Colors.orange;
            amount = '${l10n?.currency ?? 'ETB'} ${t.amount.formatted}';
            if (t.coffeeWeight != null) {
              weightLabel = '${t.coffeeWeight!.formatted} ${l10n?.kg ?? 'kg'}'
                  ' • '
                  '${l10n?.currency ?? 'ETB'} ${(t.pricePerKg ?? 0).formatted}';
            }
        }
        if (!t.isTransfer) {
          title = '$title · ${t.workerName}';
        }
        subtitle = DateFormat('MMM d, h:mm a').format(t.createdAt);
        onTap = () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WorkerDetailScreen(workerId: t.workerId),
            ),
          );
        };
        break;
      case _FeedKind.income:
        final r = item.payload as IncomeRecord;
        icon = r.kind == IncomeKind.sale
            ? Icons.point_of_sale
            : Icons.account_balance;
        amountColor = AppColors.success;
        final kindLabel = r.kind == IncomeKind.sale
            ? (r.saleCategory ?? (l10n?.manualSales ?? 'Manual Sales'))
            : (l10n?.investment ?? 'Investment');
        title = r.kind == IncomeKind.investment
            ? '$kindLabel · ${r.viewerName ?? '-'}'
            : kindLabel;
        subtitle = DateFormat('MMM d, h:mm a').format(r.createdAt);
        amount = '+${l10n?.currency ?? 'ETB'} ${r.amount.formatted}';
        onTap = () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const CompanyIncomeScreen()),
          );
        };
        break;
      case _FeedKind.expense:
        final e = item.payload as ExpenseRecord;
        icon = Icons.receipt_long;
        amountColor = AppColors.error;
        title = e.expenseCategory;
        subtitle = DateFormat('MMM d, h:mm a').format(e.createdAt);
        amount = '-${l10n?.currency ?? 'ETB'} ${e.amount.formatted}';
        onTap = () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ExpensesScreen()),
          );
        };
        break;
    }

    return Container(
      margin: EdgeInsets.only(bottom: bottomMargin),
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
      child: InkWell(
        onTap: onTapOverride ?? onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: mutedColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: amountColor,
                  ),
                ),
                if (weightLabel != null)
                  Text(
                    weightLabel,
                    style: TextStyle(fontSize: 10, color: mutedColor),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
