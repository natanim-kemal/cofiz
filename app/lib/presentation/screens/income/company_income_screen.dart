import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/income_record_model.dart';
import '../../../core/providers/income_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/utils/number_formatter.dart';
import '../../widgets/custom_header.dart';
import '../../widgets/app_toast.dart';
import 'dialogs/add_income_dialog.dart';
import '../settings/sale_categories_screen.dart';
import '../../../l10n/app_localizations.dart';

class CompanyIncomeScreen extends StatefulWidget {
  const CompanyIncomeScreen({super.key});

  @override
  State<CompanyIncomeScreen> createState() => _CompanyIncomeScreenState();
}

class _CompanyIncomeScreenState extends State<CompanyIncomeScreen> {
  int _itemsToShow = 20;
  static const int _itemsPerLoad = 20;
  DateTime? _selectedDate;

  void _loadMore() {
    setState(() => _itemsToShow += _itemsPerLoad);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

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
                      l10n.companyIncome,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.totalIncome,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<IncomeProvider>(
              builder: (context, provider, _) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  children: [
                    _buildTotalCard(context, provider),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildBreakdown(
                            context,
                            Icons.trending_up,
                            l10n.investmentIncome,
                            provider.totalInvestments,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildBreakdown(
                            context,
                            Icons.storefront,
                            l10n.salesIncome,
                            provider.totalSales,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const SaleCategoriesScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.category, size: 18),
                        label: Text(l10n.manageSaleCategories),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.incomeRecords,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                        ),
                        if (_selectedDate != null)
                          TextButton.icon(
                            onPressed: () {
                              setState(() => _selectedDate = null);
                            },
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
                            tooltip: l10n.filterByDate,
                            onPressed: _pickDate,
                            icon: const Icon(Icons.filter_alt),
                            color: AppColors.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (provider.records.isEmpty ||
                        _filteredRecords(provider.records).isEmpty)
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
                      ..._filteredRecords(provider.records)
                          .take(_itemsToShow)
                          .map((r) => _buildRecordTile(context, r)),
                      if (_filteredRecords(provider.records).length >
                          _itemsToShow)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: OutlinedButton.icon(
                            onPressed: _loadMore,
                            icon: const Icon(Icons.expand_more),
                            label: Text(
                              l10n.loadMore(_filteredRecords(provider.records)
                                      .length -
                                  _itemsToShow),
                            ),
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
                      else if (_filteredRecords(provider.records).length >
                          _itemsPerLoad)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            l10n.showingAllTransactions(
                                _filteredRecords(provider.records).length),
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
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (auth.userRole?.canCreateTransactions != true) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            onPressed: () => _showAddIncomeDialog(context),
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.add),
            label: Text(l10n.addIncome),
          );
        },
      ),
    );
  }

  Widget _buildTotalCard(BuildContext context, IncomeProvider provider) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(20),
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
            l10n.totalIncome,
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? AppColors.textMutedDark
                  : AppColors.textMutedLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${l10n.currency ?? 'ETB'} ${provider.totalIncome.formatted}',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 30,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdown(
      BuildContext context, IconData icon, String label, double value) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Color(0xFFF0A04B)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 8),
          Text(
            '${l10n.currency ?? 'ETB'} ${value.formattedCompact}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  List<IncomeRecord> _filteredRecords(List<IncomeRecord> records) {
    if (_selectedDate == null) return records;
    return records
        .where((r) =>
            r.createdAt.year == _selectedDate!.year &&
            r.createdAt.month == _selectedDate!.month &&
            r.createdAt.day == _selectedDate!.day)
        .toList();
  }

  Widget _buildRecordTile(BuildContext context, IncomeRecord record) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final title = record.kind == IncomeKind.sale
        ? (record.saleCategory ?? l10n.manualSales)
        : (l10n.viewerInvestment);
    final subtitle = record.kind == IncomeKind.investment &&
            record.viewerName != null
        ? '${record.viewerName} · ${DateFormat('MMM d, yyyy h:mm a').format(record.createdAt)}'
        : DateFormat('MMM d, yyyy h:mm a').format(record.createdAt);

    return Consumer<AuthProvider>(
      builder: (context, auth, _) => GestureDetector(
        onLongPress: auth.isAdmin
            ? () => _showRecordActions(context, record)
            : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.1),
                ),
                child: Icon(
                  record.kind == IncomeKind.sale
                      ? Icons.storefront
                      : Icons.trending_up,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
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
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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
        ),
      ),
    );
  }

  Future<void> _showAddIncomeDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => const AddIncomeDialog(),
    );
  }

  Future<void> _editRecord(BuildContext context, IncomeRecord record) async {
    await showDialog(
      context: context,
      builder: (context) => AddIncomeDialog(existing: record),
    );
  }

  Future<void> _deleteRecord(
      BuildContext context, IncomeRecord record) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteIncomeTitle),
        content: Text(l10n.deleteIncomeConfirmation(
            '${l10n.currency} ${record.amount.formatted}')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                Text(l10n.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final provider = Provider.of<IncomeProvider>(context, listen: false);
    final success = await provider.deleteIncome(record.id);

    if (context.mounted) {
      if (success) {
        AppToast.show(l10n.incomeDeleted, success: true);
      } else {
        AppToast.show(provider.errorMessage ?? l10n.failedToDeleteIncome);
      }
    }
  }

  Future<void> _showRecordActions(
      BuildContext context, IncomeRecord record) async {
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

    if (!context.mounted || action == null) return;
    if (action == 'edit') {
      await _editRecord(context, record);
    } else if (action == 'delete') {
      await _deleteRecord(context, record);
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
}
