import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/income_record_model.dart';
import '../../../../core/providers/income_provider.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/audit_provider.dart';
import '../../../../core/services/income_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../widgets/app_toast.dart';

class AddIncomeDialog extends StatefulWidget {
  final IncomeRecord? existing;

  const AddIncomeDialog({super.key, this.existing});

  @override
  State<AddIncomeDialog> createState() => _AddIncomeDialogState();
}

class _AddIncomeDialogState extends State<AddIncomeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sourceController = TextEditingController();

  IncomeKind _kind = IncomeKind.investment;
  String? _selectedSaleCategory;
  List<String> _saleCategories = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _kind = existing.kind;
      _amountController.text = existing.amount.toStringAsFixed(2);
      _descriptionController.text = existing.description ?? '';
      _sourceController.text = existing.viewerName ?? '';
      _selectedSaleCategory = existing.saleCategory;
    }
    _loadCategories();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final categories = await IncomeService().getSaleCategories();
    if (mounted) {
      setState(() {
        _saleCategories = categories;
        _selectedSaleCategory ??=
            categories.isNotEmpty ? categories.first : null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<IncomeProvider>(context, listen: false);
    final source = _sourceController.text.trim();

    final record = IncomeRecord(
      id: widget.existing?.id ?? '',
      kind: _kind,
      amount: amount,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      createdBy: widget.existing?.createdBy ?? auth.user?.uid ?? 'unknown',
      createdByName:
          widget.existing?.createdByName ?? auth.user?.displayName ?? '',
      viewerId:
          _kind == IncomeKind.investment && source.isNotEmpty ? source : null,
      viewerName:
          _kind == IncomeKind.investment && source.isNotEmpty ? source : null,
      saleCategory: _kind == IncomeKind.sale ? _selectedSaleCategory : null,
    );

    setState(() => _isSubmitting = true);
    final success = widget.existing != null
        ? await provider.updateIncome(record)
        : await provider.addIncome(record);
    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        Navigator.pop(context, true);
        AppToast.show(
          AppLocalizations.of(context)!.incomeRecorded,
          success: true,
        );
        // Audit is best-effort and must never block closing the dialog
        // offline (Firestore add hangs until network). Fire-and-forget.
        final auditProvider =
            Provider.of<AuditProvider>(context, listen: false);
        final userName = auth.user?.displayName ?? auth.user?.email ?? '';
        unawaited(auditProvider.logIncomeRecorded(
          userId: auth.user?.uid ?? 'unknown',
          userName: userName,
          incomeId: record.id,
          kind: _kind.name,
          amount: amount,
        ));
      } else {
        AppToast.show(provider.errorMessage ?? 'Failed to record income');
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
                  widget.existing != null ? l10n.editIncome : l10n.addIncome,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.headlineMedium?.color,
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<IncomeKind>(
                  segments: [
                    ButtonSegment(
                      value: IncomeKind.investment,
                      label: Text(l10n.investment),
                      icon: const Icon(Icons.account_balance),
                    ),
                    ButtonSegment(
                      value: IncomeKind.sale,
                      label: Text(l10n.sale),
                      icon: const Icon(Icons.point_of_sale),
                    ),
                  ],
                  selected: {_kind},
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: AppColors.primary,
                    selectedForegroundColor: Colors.white,
                    foregroundColor:
                        isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    side: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    ),
                  ),
                  onSelectionChanged: (selection) {
                    setState(() => _kind = selection.first);
                  },
                ),
                const SizedBox(height: 16),
                if (_kind == IncomeKind.investment) ...[
                  TextFormField(
                    controller: _sourceController,
                    decoration: InputDecoration(
                      labelText: l10n.selectSource,
                      hintText: l10n.enterSourceName,
                      prefixIcon:
                          const Icon(Icons.person, color: AppColors.primary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor:
                          isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                    ),
                  ),
                ] else ...[
                  DropdownButtonFormField<String>(
                    initialValue:
                        _saleCategories.contains(_selectedSaleCategory)
                            ? _selectedSaleCategory
                            : null,
                    decoration: InputDecoration(
                      labelText: l10n.selectSaleCategory,
                      prefixIcon:
                          const Icon(Icons.category, color: AppColors.primary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor:
                          isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                    ),
                    items: _saleCategories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _selectedSaleCategory = value),
                    validator: (value) =>
                        value == null ? l10n.selectSaleCategory : null,
                  ),
                ],
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
                    prefixIcon: const Icon(Icons.attach_money,
                        color: AppColors.primary),
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
                    labelText: l10n.incomeDescription,
                    hintText: l10n.notesOptional,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor:
                        isDark ? Colors.grey.shade800 : Colors.grey.shade50,
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
