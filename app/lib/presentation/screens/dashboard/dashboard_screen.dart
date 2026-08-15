import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/worker_provider.dart';
import '../../../core/providers/transaction_provider.dart';
import '../../../core/providers/income_provider.dart';
import '../../../core/providers/expense_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/notification_provider.dart';
import '../../../core/models/worker_model.dart';
import '../../../core/utils/number_formatter.dart';
import '../../../main.dart';
import '../../dialogs/ping_dialog.dart';
import '../../widgets/activity_feed_list.dart';
import '../../widgets/notification_badge.dart';
import '../notifications/notifications_screen.dart';
import '../income/company_income_screen.dart';
import '../income/my_investments_screen.dart';
import '../expense/expenses_screen.dart';
import '../transaction/transaction_dialog.dart';
import '../../widgets/custom_header.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _showTotalActivity = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final transactionProvider =
          Provider.of<TransactionProvider>(context, listen: false);
      transactionProvider.loadTodayTotals();
      transactionProvider.loadAllTransactions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final workerProvider = Provider.of<WorkerProvider>(context);
    final transactionProvider = Provider.of<TransactionProvider>(context);
    final incomeProvider = Provider.of<IncomeProvider>(context);
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Robust Localization: Allow null, use fallbacks
    final AppLocalizations? localizations = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async {
          await workerProvider.refresh();
          await transactionProvider.loadTodayTotals();
          transactionProvider.loadAllTransactions();
        },
        child: Column(
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
                            localizations?.welcomeBack ?? 'Welcome Back,',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            authProvider.user?.displayName ?? 'User',
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
                          // Admin Ping All Button
                          if (authProvider.isAdmin)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: IconButton(
                                icon: const Icon(Icons.campaign,
                                    color: Colors.white),
                                tooltip: localizations?.pingAllWorkers ??
                                    'Ping All Collectors',
                                onPressed: () =>
                                    _showPingAllDialog(context, authProvider),
                              ),
                            ),
                          NotificationBadge(
                            child: IconButton(
                              icon: const Icon(
                                Icons.notifications_outlined,
                                color: Colors.white,
                                size: 28,
                              ),
                              tooltip: localizations?.notifications ??
                                  'Notifications',
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Compact Stats (Moved Up)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 12),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Colors.black.withOpacity(isDark ? 0.2 : 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildCompactStat(
                            context,
                            Icons.trending_up,
                            '${localizations?.currency ?? 'ETB'} ${incomeProvider.totalIncome.formattedCompact}',
                            localizations?.investment ?? 'Investment',
                            AppColors.primary,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => authProvider.isViewer
                                      ? const MyInvestmentsScreen()
                                      : const CompanyIncomeScreen(),
                                ),
                              );
                            },
                          ),
                          _buildContainerDivider(isDark),
                          _buildCompactStat(
                            context,
                            Icons.people,
                            '${workerProvider.activeToday}',
                            localizations?.collectors ?? 'Collectors',
                            AppColors.primary,
                            onTap: () => MainLayout.navigateTo(1),
                          ),
_buildContainerDivider(isDark),
                          _buildCompactStat(
                            context,
                            Icons.receipt_long,
                            '${localizations?.currency ?? 'ETB'} ${expenseProvider.totalExpenses.formattedCompact}',
                            localizations?.expenses ?? 'Expenses',
                            AppColors.primary,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const ExpensesScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Today's Overview Card (Moved Down)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primary,
                            AppColors.primary.withOpacity(0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.account_balance_wallet,
                                color: Colors.white,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _showTotalActivity
                                      ? (localizations?.totalActivity ??
                                          'Total Activity')
                                      : (localizations?.todaysActivity ??
                                          "Today's Activity"),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => setState(
                                    () => _showTotalActivity =
                                        !_showTotalActivity),
                                icon: const Icon(
                                  Icons.swap_horiz,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                tooltip: 'Toggle Today / Total',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTodayStatItem(
                                  localizations?.moneyIn ?? 'Money In',
                                  _showTotalActivity
                                      ? '${localizations?.currency ?? "ETB"} ${_totalMoneyIn(transactionProvider, incomeProvider, expenseProvider).formatted}'
                                      : '${localizations?.currency ?? "ETB"} ${_todayMoneyIn(transactionProvider, incomeProvider, expenseProvider).formatted}',
                                  Icons.arrow_downward,
                                  Colors.white,
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 50,
                                color: Colors.white24,
                              ),
                              Expanded(
                                child: _buildTodayStatItem(
                                  localizations?.moneyOut ?? 'Money Out',
                                  _showTotalActivity
                                      ? '${localizations?.currency ?? "ETB"} ${_totalMoneyOut(transactionProvider, expenseProvider).formatted}'
                                      : '${localizations?.currency ?? "ETB"} ${_todayMoneyOut(transactionProvider, expenseProvider).formatted}',
                                  Icons.arrow_upward,
                                  Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Divider(color: Colors.white24),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                localizations?.netBalance ?? 'Net Balance',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                _showTotalActivity
                                    ? '${localizations?.currency ?? "ETB"} ${_totalNet(transactionProvider, incomeProvider, expenseProvider).formatted}'
                                    : '${localizations?.currency ?? "ETB"} ${_todayNet(transactionProvider, incomeProvider, expenseProvider).formatted}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    _buildEntrySection(),

                    const SizedBox(height: 24),

                    // Latest Transactions Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          localizations?.latestTransactions ??
                              'Latest Transactions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                        ),
                        TextButton(
                          onPressed: () => MainLayout.navigateTo(2),
                          child: Text(
                            localizations?.viewAll ?? 'View All',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ActivityFeedList(
                      transactions: transactionProvider.allTransactions,
                      incomeRecords: incomeProvider.records,
                      expenseRecords: expenseProvider.records,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntrySection() {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations?.recordTransactions ?? 'Record Transactions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildEntryButton(
                  Icons.add_circle,
                  localizations?.distribute ?? 'Distribute',
                  () => _pickWorkerForEntry('distribution'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildEntryButton(
                  Icons.remove_circle,
                  localizations?.returnMoney ?? 'Return',
                  () => _pickWorkerForEntry('return'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildEntryButton(
                  Icons.shopping_cart,
                  localizations?.recordPurchase ?? 'Purchase',
                  () => _pickWorkerForEntry('purchase'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEntryButton(
      IconData icon, String label, VoidCallback onTap) {
    const warmOrange = Color(0xFFF0A04B);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: warmOrange.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: warmOrange, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: warmOrange,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _pickWorkerForEntry(String type) {
    final workerProvider = Provider.of<WorkerProvider>(context, listen: false);
    final workers = workerProvider.workers.where((w) => w.isActive).toList();

    if (workers.isEmpty) {
      AppToast.show('No collectors available');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _WorkerPickerSheet(
        workers: workers,
        type: type,
      ),
    );
  }

  double _todayMoneyIn(
      TransactionProvider tp, IncomeProvider ip, ExpenseProvider ep) {
    return tp.todayReturned +
        tp.todayPurchased +
        ip.todayInvestmentIncome +
        ip.todayManualSales;
  }

  double _todayMoneyOut(TransactionProvider tp, ExpenseProvider ep) {
    return tp.todayDistributed + ep.todayExpenses;
  }

  double _todayNet(
      TransactionProvider tp, IncomeProvider ip, ExpenseProvider ep) {
    return _todayMoneyIn(tp, ip, ep) - _todayMoneyOut(tp, ep);
  }

  double _totalMoneyIn(
      TransactionProvider tp, IncomeProvider ip, ExpenseProvider ep) {
    final transactions = tp.allTransactions;
    double returned = 0;
    double purchased = 0;
    for (final t in transactions) {
      switch (t.type.toLowerCase()) {
        case 'return':
          returned += t.amount;
          break;
        case 'purchase':
          purchased += t.amount;
          break;
      }
    }
    return returned + purchased + ip.totalInvestments + ip.totalSales;
  }

  double _totalMoneyOut(TransactionProvider tp, ExpenseProvider ep) {
    final transactions = tp.allTransactions;
    double distributed = 0;
    for (final t in transactions) {
      if (t.type.toLowerCase() == 'distribution') {
        distributed += t.amount;
      }
    }
    return distributed + ep.totalExpenses;
  }

  double _totalNet(
      TransactionProvider tp, IncomeProvider ip, ExpenseProvider ep) {
    final net = _totalMoneyIn(tp, ip, ep) - _totalMoneyOut(tp, ep);
    return net < 0 ? 0 : net;
  }

  Widget _buildTodayStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color.withOpacity(0.8), size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactStat(BuildContext context, IconData icon, String value,
      String label, Color color,
      {VoidCallback? onTap}) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13.2,
            color: Color(0xFFF0A04B),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: content,
    );
  }

  Future<void> _showPingAllDialog(
      BuildContext context, AuthProvider authProvider) async {
    final localizations = AppLocalizations.of(context);
    await showDialog(
      context: context,
      builder: (context) => PingDialog(
        title: localizations?.pingAllWorkers ?? 'Ping All Collectors',
        messageLabel:
            localizations?.messageToAllWorkers ?? 'Message to all collectors',
        onSend: (message) async {
          final notificationProvider =
              Provider.of<NotificationProvider>(context, listen: false);

          await notificationProvider.sendGlobalPing(
            title: localizations?.announcement ?? 'Announcement',
            body: message,
            senderName: authProvider.user?.displayName ??
                localizations?.admin ??
                'Admin',
            senderId: authProvider.user?.uid ?? '',
          );

          if (context.mounted) {
            AppToast.show(localizations?.notificationSentToAll ??
                'Notification sent to all collectors');
          }
        },
      ),
    );
  }

  Widget _buildContainerDivider(bool isDark) {
    return Container(
      width: 1,
      height: 40,
      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
    );
  }
}

class _WorkerPickerSheet extends StatefulWidget {
  final List<Worker> workers;
  final String type;

  const _WorkerPickerSheet({
    required this.workers,
    required this.type,
  });

  @override
  State<_WorkerPickerSheet> createState() => _WorkerPickerSheetState();
}

class _WorkerPickerSheetState extends State<_WorkerPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final filtered = widget.workers
        .where((w) =>
            _query.isEmpty ||
            w.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              localizations?.selectCollector ?? 'Select Collector',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: localizations?.searchCollector ?? 'Search collectors',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      localizations?.noCollectorsFound ?? 'No collectors found',
                      style: TextStyle(
                          color: isDark ? Colors.grey.shade400 : Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final worker = filtered[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(worker.name.isNotEmpty
                              ? worker.name[0].toUpperCase()
                              : '?'),
                        ),
                        title: Text(worker.name),
                        subtitle: Text(
                          '${localizations?.currentBalance ?? 'Balance'}: '
                          '${worker.currentBalance.asCurrency}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(context);
                          showDialog(
                            context: context,
                            builder: (context) => TransactionDialog(
                              worker: worker,
                              type: widget.type,
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
