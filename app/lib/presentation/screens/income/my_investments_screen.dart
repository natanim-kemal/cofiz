import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/income_record_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/income_service.dart';
import '../../../core/utils/number_formatter.dart';
import '../../widgets/custom_header.dart';
import '../../../l10n/app_localizations.dart';

class MyInvestmentsScreen extends StatefulWidget {
  const MyInvestmentsScreen({super.key});

  @override
  State<MyInvestmentsScreen> createState() => _MyInvestmentsScreenState();
}

class _MyInvestmentsScreenState extends State<MyInvestmentsScreen> {
  List<IncomeRecord> _records = [];
  StreamSubscription<List<IncomeRecord>>? _subscription;
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _loadedExtraPages = false;
  int _totalCount = 0;
  double _totalAmount = 0.0;

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final uid = auth.user?.uid;
    if (uid == null) return;
    setState(() => _isLoadingMore = true);
    final page =
        await IncomeService().getIncomeForViewerPage(uid, startAfter: _lastDoc);
    if (!mounted) return;
    final knownIds = _records.map((r) => r.id).toSet();
    setState(() {
      _records = [
        ..._records,
        ...page.items.where((r) => !knownIds.contains(r.id)),
      ];
      _lastDoc = page.lastDoc;
      _hasMore = page.hasMore;
      _loadedExtraPages = true;
      _isLoadingMore = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final uid = auth.user?.uid;
    if (uid == null) return;
    _subscription =
        IncomeService().getIncomeForViewerPageStream(uid).listen((records) {
      if (mounted)
        setState(() {
          if (_loadedExtraPages) {
            final tail = _records.length > records.length
                ? _records.sublist(records.length)
                : <IncomeRecord>[];
            _records = [...records, ...tail];
          } else {
            _records = records;
            _hasMore = records.length >= 20;
          }
        });
    });
    IncomeService().getIncomeCount(viewerId: uid).then((count) {
      if (mounted && count != null) setState(() => _totalCount = count);
    });
    IncomeService()
        .getIncomeTotalByKind(IncomeKind.investment, viewerId: uid)
        .then((amount) {
      if (mounted && amount != null) setState(() => _totalAmount = amount);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final total = _totalAmount;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          CustomHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  children: [
                    if (Navigator.canPop(context))
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: IconButton(
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    Text(
                      l10n.myInvestments,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, Color(0xFF6A8DEE)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.totalIncome,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${l10n.currency ?? 'ETB'} ${total.formattedCompact}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_records.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        l10n.noTransactionsYet,
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  )
                else ...[
                  ..._records.map((r) => _buildRecordTile(context, r)),
                  if (_hasMore)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: OutlinedButton.icon(
                        onPressed: _isLoadingMore ? null : _loadMore,
                        icon: _isLoadingMore
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.primary),
                              )
                            : const Icon(Icons.expand_more),
                        label: Text(l10n.loadMore),
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
                    )
                  else if (_totalCount > 20)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        l10n.showingAllTransactions(_totalCount),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.textMutedDark
                              : AppColors.textMutedLight,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTile(BuildContext context, IncomeRecord record) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance, color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.investment,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM d, yyyy h:mm a').format(record.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textMutedDark
                        : AppColors.textMutedLight,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '+${l10n.currency ?? 'ETB'} ${record.amount.formatted}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
