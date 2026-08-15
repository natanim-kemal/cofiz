import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/expense_record_model.dart';
import '../../../../core/providers/expense_provider.dart';
import '../../../../core/providers/transaction_provider.dart';
import '../../../../core/providers/income_provider.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/services/expense_service.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../widgets/app_toast.dart';

class AddExpenseDialog extends StatefulWidget {
  final ExpenseRecord? existing;

  const AddExpenseDialog({super.key, this.existing});

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<String> _categories = [];
  String? _selectedCategory;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _amountController.text = existing.amount.toStringAsFixed(2);
      _descriptionController.text = existing.description ?? '';
      _selectedCategory = existing.expenseCategory;
    }
    _loadCategories();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final categories = await ExpenseService().getExpenseCategories();
    if (mounted) {
      setState(() {
        _categories = categories;
        _selectedCategory ??= categories.isNotEmpty ? categories.first : null;
      });
    }
  }

  double _availableBalance(TransactionProvider tp, IncomeProvider ip,
      ExpenseProvider ep) {
    double moneyIn = ip.totalInvestments + ip.totalSales;
    double moneyOut = ep.totalExpenses;
    for (final t in tp.allTransactions) {
      switch (t.type.toLowerCase()) {
        case 'return':
        case 'purchase':
          moneyIn += t.amount;
          break;
        case 'distribution':
          moneyOut += t.amount;
          break;
      }
    }
    // When editing, the existing expense is already in totalExpenses
    if (widget.existing != null) {
      moneyOut -= widget.existing!.amount;
    }
    final net = moneyIn - moneyOut;
    return net < 0 ? 0 : net;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<ExpenseProvider>(context, listen: false);
    final transactionProvider =
        Provider.of<TransactionProvider>(context, listen: false);
    final incomeProvider = Provider.of<IncomeProvider>(context, listen: false);

    if (amount > _availableBalance(
        transactionProvider, incomeProvider, provider)) {
      if (mounted) {
        AppToast.show(
            AppLocalizations.of(context)!.insufficientBalance);
      }
      return;
    }

    final record = ExpenseRecord(
      id: widget.existing?.id ?? '',
      amount: amount,
      expenseCategory: _selectedCategory ?? 'Other',
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      createdBy: widget.existing?.createdBy ?? auth.user?.uid ?? 'unknown',
      createdByName:
          widget.existing?.createdByName ?? auth.user?.displayName ?? '',
    );

    setState(() => _isSubmitting = true);
    final success = widget.existing != null
        ? await provider.updateExpense(record)
        : await provider.addExpense(record);
    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        Navigator.pop(context, true);
        AppToast.show(
          AppLocalizations.of(context)!.expenseRecorded,
          success: true,
        );
      } else {
        AppToast.show(provider.errorMessage ?? 'Failed to record expense');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.dialogBackgroundColor,
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.existing != null ? l10n.editExpense : l10n.addExpense,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.headlineMedium?.color,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _categories.contains(_selectedCategory)
                      ? _selectedCategory
                      : null,
                  decoration: InputDecoration(
                    labelText: l10n.selectExpenseCategory,
                    prefixIcon: const Icon(Icons.category),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor:
                        isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                  ),
                  items: _categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedCategory = value),
                  validator: (value) =>
                      value == null ? l10n.selectExpenseCategory : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Amount (${l10n.currency ?? 'ETB'})',
                    prefixIcon: const Icon(Icons.attach_money),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor:
                        isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.amountIsRequired;
                    }
                    final val = double.tryParse(value);
                    if (val == null || val <= 0) return l10n.invalidAmount;
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: l10n.expenseDescription,
                    hintText: l10n.notesOptional,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor:
                        isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.currentBalanceInfo(
                            AppLocalizations.of(context)?.currency ?? 'ETB',
                            _availableBalance(
                              Provider.of<TransactionProvider>(context,
                                  listen: false),
                              Provider.of<IncomeProvider>(context,
                                  listen: false),
                              Provider.of<ExpenseProvider>(context,
                                  listen: false),
                            ).formatted,
                          ),
                          style: const TextStyle(color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _isSubmitting ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(l10n.confirm),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
