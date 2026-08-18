import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../../core/models/worker_model.dart';
import '../../../core/models/transaction_model.dart';
import '../../../core/constants/coffee_types.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/transaction_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';

class TransactionDialog extends StatefulWidget {
  final Worker worker;
  final String type; // 'distribution', 'return', 'purchase'
  final MoneyTransaction? existing;

  const TransactionDialog({
    super.key,
    required this.worker,
    required this.type,
    this.existing,
  });

  @override
  State<TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends State<TransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  // Purchase specific
  final _weightController = TextEditingController();
  final _priceController = TextEditingController();
  CoffeeType? _selectedCoffeeType;

  bool _isLoading = false;
  File? _receiptImage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _amountController.text = existing.amount.toStringAsFixed(2);
      _notesController.text = existing.notes ?? '';
      _selectedCoffeeType = existing.coffeeType == null
          ? null
          : CoffeeType.values
              .where((t) => t.name == existing.coffeeType)
              .firstOrNull;
      if (existing.coffeeWeight != null) {
        _weightController.text = existing.coffeeWeight.toString();
      }
      if (existing.pricePerKg != null) {
        _priceController.text = existing.pricePerKg.toString();
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    _weightController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  String get title {
    if (widget.existing != null) {
      return AppLocalizations.of(context)!.editTransaction;
    }
    switch (widget.type) {
      case 'distribution':
        return AppLocalizations.of(context)!.distributeMoney;
      case 'return':
        return AppLocalizations.of(context)!.returnMoneyTitle;
      case 'purchase':
        return AppLocalizations.of(context)!.recordPurchase;
      default:
        return AppLocalizations.of(context)!.transaction;
    }
  }

  IconData get icon {
    switch (widget.type) {
      case 'distribution':
        return Icons.add_circle;
      case 'return':
        return Icons.remove_circle;
      case 'purchase':
        return Icons.shopping_cart;
      default:
        return Icons.receipt;
    }
  }

  Color get color {
    const warmOrange = AppColors.primary;
    switch (widget.type) {
      case 'distribution':
        return warmOrange;
      case 'return':
        return warmOrange;
      case 'purchase':
        return warmOrange;
      default:
        return AppColors.primary;
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _receiptImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
            AppLocalizations.of(context)!.errorPickingImage(e.toString()));
      }
    }
  }

  void _updateTotalCost() {
    if (widget.type != 'purchase') return;

    final weight = double.tryParse(_weightController.text.trim()) ?? 0;
    final price = double.tryParse(_priceController.text.trim()) ?? 0;

    if (weight > 0 && price > 0) {
      final total = weight * price;
      _amountController.text = total.toStringAsFixed(2);
    } else {
      _amountController.text = '';
    }
    setState(() {}); // Trigger rebuild for commission preview
  }

  String _calculateCommission() {
    final weight = double.tryParse(_weightController.text.trim()) ?? 0;
    if (weight <= 0) return '0.00 ETB';

    final commission = weight * widget.worker.commissionRate;
    return '${commission.toStringAsFixed(2)} ETB';
  }

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final notes = _notesController.text.trim();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final transactionProvider =
        Provider.of<TransactionProvider>(context, listen: false);

    // Upload receipt if exists
    String? receiptUrl;
    if (_receiptImage != null) {
      receiptUrl = await transactionProvider.uploadReceipt(_receiptImage!.path);
      if (receiptUrl == null) {
        // Upload failed
        if (mounted) {
          setState(() => _isLoading = false);
          AppToast.show(transactionProvider.errorMessage ??
              AppLocalizations.of(context)!.failedToUploadReceipt);
        }
        return;
      }
    }

    bool success = false;

    if (widget.existing != null) {
      final existing = widget.existing!;
      final weight = double.tryParse(_weightController.text.trim());
      final price = double.tryParse(_priceController.text.trim());
      final commission = widget.type == 'purchase'
          ? (weight ?? 0) * widget.worker.commissionRate
          : null;

      final updated = MoneyTransaction(
        id: existing.id,
        workerId: existing.workerId,
        workerName: existing.workerName,
        type: existing.type,
        amount: amount,
        notes: notes.isEmpty ? null : notes,
        receiptUrl: receiptUrl ?? existing.receiptUrl,
        createdAt: existing.createdAt,
        createdBy: existing.createdBy,
        approved: existing.approved,
        coffeeType: widget.type == 'purchase'
            ? _selectedCoffeeType?.name
            : existing.coffeeType,
        coffeeWeight:
            widget.type == 'purchase' ? weight : existing.coffeeWeight,
        pricePerKg: widget.type == 'purchase' ? price : existing.pricePerKg,
        commissionAmount:
            widget.type == 'purchase' ? commission : existing.commissionAmount,
      );
      success = await transactionProvider.updateTransaction(updated);
    } else {
      switch (widget.type) {
        case 'distribution':
          success = await transactionProvider.distributeMoneyToWorker(
            workerId: widget.worker.id,
            workerName: widget.worker.name,
            amount: amount,
            createdBy: authProvider.user?.uid ?? 'unknown',
            notes: notes.isEmpty ? null : notes,
            receiptUrl: receiptUrl,
          );
          break;
        case 'return':
          success = await transactionProvider.returnMoneyFromWorker(
            workerId: widget.worker.id,
            workerName: widget.worker.name,
            amount: amount,
            createdBy: authProvider.user?.uid ?? 'unknown',
            notes: notes.isEmpty ? null : notes,
            receiptUrl: receiptUrl,
          );
          break;
        case 'purchase':
          // For purchase, amount is calculated from weight * price (if provided) or strictly validation
          // But for storage, we pass specific fields.
          final weight = double.tryParse(_weightController.text.trim());
          final price = double.tryParse(_priceController.text.trim());

          // Commission = Weight * Worker's Rate
          final commission = (weight ?? 0) * widget.worker.commissionRate;

          success = await transactionProvider.recordCoffeePurchase(
            workerId: widget.worker.id,
            workerName: widget.worker.name,
            amount: amount, // Total Cost (Weight * Price)
            createdBy: authProvider.user?.uid ?? 'unknown',
            notes: notes.isEmpty ? null : notes,
            receiptUrl: receiptUrl,
            coffeeType: _selectedCoffeeType?.name,
            weight: weight,
            pricePerKg: price,
            commission: commission,
          );
          break;
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);

      if (success) {
        Navigator.pop(context, true);
        AppToast.show(
          AppLocalizations.of(context)!.transactionCompleted,
          success: true,
        );
      } else {
        AppToast.show(transactionProvider.errorMessage ??
            AppLocalizations.of(context)!.failedToComplete);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
              children: [
                // Icon
                Icon(icon, color: AppColors.primary, size: 40),

                const SizedBox(height: 16),

                // Title
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.headlineMedium?.color,
                  ),
                ),

                const SizedBox(height: 8),

                // Worker name
                Text(
                  widget.worker.name,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? AppColors.textMutedDark
                        : AppColors.textMutedLight,
                  ),
                ),

                const SizedBox(height: 24),

                if (widget.type != 'purchase') ...[
                  // Normal Amount Field for Distribution/Return
                  TextFormField(
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!
                          .amountWithCurrency(
                              AppLocalizations.of(context)?.currency ?? 'ETB'),
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
                        return AppLocalizations.of(context)!.amountIsRequired;
                      }
                      final val = double.tryParse(value);
                      if (val == null || val <= 0) {
                        return AppLocalizations.of(context)!.invalidAmount;
                      }
                      if (widget.type == 'return' &&
                          val > widget.worker.currentBalance) {
                        return AppLocalizations.of(context)!
                            .insufficientBalance;
                      }
                      return null;
                    },
                  ),
                ] else ...[
                  // Purchase Fields: Coffee Type, Weight & Price
                  DropdownButtonFormField<CoffeeType>(
                    initialValue: _selectedCoffeeType,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.coffeeType,
                      prefixIcon:
                          const Icon(Icons.category, color: AppColors.primary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor:
                          isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                    ),
                    items: CoffeeType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.displayName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCoffeeType = value;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return AppLocalizations.of(context)!.selectCoffeeType;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _weightController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)!.weightKg,
                            suffixText: 'Kg',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade50,
                          ),
                          onChanged: (val) => _updateTotalCost(),
                          validator: (val) => (val == null || val.isEmpty)
                              ? AppLocalizations.of(context)!.required
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)!.pricePerKg,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade50,
                          ),
                          onChanged: (val) => _updateTotalCost(),
                          validator: (val) => (val == null || val.isEmpty)
                              ? AppLocalizations.of(context)!.required
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Read-only Total Cost
                  TextFormField(
                    controller: _amountController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText:
                          AppLocalizations.of(context)!.totalCostCalculated,
                      prefixIcon:
                          const Icon(Icons.calculate, color: AppColors.primary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: isDark ? Colors.black26 : Colors.grey.shade200,
                    ),
                  ),

                  const SizedBox(height: 8),
                  // Commission Preview
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.workerCommission,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _calculateCommission(),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                // Notes field
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.notesOptional,
                    hintText: AppLocalizations.of(context)!.addNotesHere,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor:
                        isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                  ),
                ),

                const SizedBox(height: 16),

                // Receipt Image Picker
                InkWell(
                  onTap: _pickImage,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                      color:
                          isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.camera_alt, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _receiptImage != null
                                ? AppLocalizations.of(context)!.receiptSelected
                                : AppLocalizations.of(context)!.addReceiptPhoto,
                            style: TextStyle(
                              color: _receiptImage != null
                                  ? Colors.green
                                  : (isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600),
                              fontWeight: _receiptImage != null
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (_receiptImage != null)
                          const Icon(Icons.check_circle,
                              color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
                if (_receiptImage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _receiptImage!,
                            height: 100,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _receiptImage = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _isLoading ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(AppLocalizations.of(context)!.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitTransaction,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(AppLocalizations.of(context)!.confirm),
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
