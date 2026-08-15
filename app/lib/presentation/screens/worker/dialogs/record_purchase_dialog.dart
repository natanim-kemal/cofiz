import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/models/worker_model.dart';
import '../../../../core/constants/coffee_types.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/services/area_service.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/transaction_provider.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../widgets/app_toast.dart';

class RecordPurchaseDialog extends StatefulWidget {
  final Worker worker;
  final VoidCallback onSuccess;

  const RecordPurchaseDialog({
    super.key,
    required this.worker,
    required this.onSuccess,
  });

  @override
  State<RecordPurchaseDialog> createState() => _RecordPurchaseDialogState();
}

class _RecordPurchaseDialogState extends State<RecordPurchaseDialog> {
  final quantityController = TextEditingController();
  final priceController = TextEditingController();
  final placeController = TextEditingController();
  final notesController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  CoffeeType? selectedCoffeeType;
  // selectedArea removed, used placeController instead
  List<String> areas = [];
  bool isLoading = false;
  final AreaService _areaService = AreaService();

  // Calculated values
  double get totalAmount {
    final qty = double.tryParse(quantityController.text) ?? 0;
    final price = double.tryParse(priceController.text) ?? 0;
    return qty * price;
  }

  double get commissionAmount {
    final qty = double.tryParse(quantityController.text) ?? 0;
    return qty * widget.worker.commissionRate;
  }

  @override
  void initState() {
    super.initState();
    _loadAreas();
    placeController.addListener(() => setState(() {}));
  }

  Future<void> _loadAreas() async {
    final loadedAreas = await _areaService.getAreas();
    if (mounted) {
      setState(() {
        areas = loadedAreas;
      });
    }
  }

  @override
  void dispose() {
    quantityController.dispose();
    priceController.dispose();
    placeController.dispose();
    notesController.dispose();
    super.dispose();
  }

  void _updateCalculations() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Row(
                  children: [
                    const Icon(Icons.local_cafe, color: Colors.brown, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)!.recordCoffeePurchaseTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.recordCoffeePurchaseSubtitle,
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 24),

                // Coffee Type Dropdown
                DropdownButtonFormField<CoffeeType>(
                  value: selectedCoffeeType,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.coffeeTypeLabel,
                    prefixIcon: const Icon(Icons.category),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor:
                        isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                  ),
                  items: CoffeeType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.displayName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedCoffeeType = value;
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

                // Quantity and Price Row
                Row(
                  children: [
                    // Quantity field
                    Expanded(
                      child: TextFormField(
                        controller: quantityController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText:
                              AppLocalizations.of(context)!.quantityKgLabel,
                          prefixIcon: const Icon(Icons.scale),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade100,
                        ),
                        onChanged: (_) => _updateCalculations(),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return AppLocalizations.of(context)!.required;
                          }
                          final qty = double.tryParse(value);
                          if (qty == null || qty <= 0) {
                            return AppLocalizations.of(context)!.invalidAmount;
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Price per Kg field
                    Expanded(
                      child: TextFormField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!
                              .pricePerKgLabel(
                                  AppLocalizations.of(context)?.currency ??
                                      'ETB'),
                          prefixIcon: const Icon(Icons.attach_money),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade100,
                        ),
                        onChanged: (_) => _updateCalculations(),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return AppLocalizations.of(context)!.required;
                          }
                          final price = double.tryParse(value);
                          if (price == null || price <= 0) {
                            return AppLocalizations.of(context)!.invalidAmount;
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Calculation Summary Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.brown.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.brown.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.totalAmount,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            '${AppLocalizations.of(context)?.currency ?? 'ETB'} ${totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.brown,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.paid,
                                  size: 16, color: Colors.green.shade600),
                              const SizedBox(width: 4),
                              Text(
                                AppLocalizations.of(context)!.yourCommission,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey.shade300
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${AppLocalizations.of(context)?.currency ?? 'ETB'} ${commissionAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(context)!.commissionRateInfo(
                            AppLocalizations.of(context)?.currency ?? 'ETB',
                            widget.worker.commissionRate.toStringAsFixed(2)),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Quick Pick Areas
                Text(
                  AppLocalizations.of(context)!.purchaseLocation,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                if (areas.isEmpty)
                  Text(
                    AppLocalizations.of(context)!.noAreasConfigured,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: areas
                        .map((area) => _buildAreaChip(area, isDark))
                        .toList(),
                  ),
                const SizedBox(height: 12),

                // Place field (optional custom input)
                TextFormField(
                  controller: placeController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.placeLocationLabel,
                    prefixIcon: const Icon(Icons.place),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor:
                        isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                  ),
                ),
                const SizedBox(height: 12),

                // Notes field
                TextFormField(
                  controller: notesController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.notesDetailsLabel,
                    prefixIcon: const Icon(Icons.note),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor:
                        isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Current balance info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: totalAmount > widget.worker.currentBalance
                        ? Colors.red.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: totalAmount > widget.worker.currentBalance
                        ? Border.all(color: Colors.red.withOpacity(0.5))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        totalAmount > widget.worker.currentBalance
                            ? Icons.warning_amber_rounded
                            : Icons.account_balance_wallet,
                        color: totalAmount > widget.worker.currentBalance
                            ? Colors.red
                            : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context)!.availableBalance(
                            AppLocalizations.of(context)?.currency ?? 'ETB',
                            widget.worker.currentBalance.toStringAsFixed(2)),
                        style: TextStyle(
                          color: totalAmount > widget.worker.currentBalance
                              ? Colors.red
                              : Colors.orange,
                        ),
                      ),
                      if (totalAmount > widget.worker.currentBalance)
                        Text(
                          AppLocalizations.of(context)!.insufficient,
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            if (formKey.currentState!.validate()) {
                              // Check balance
                              if (totalAmount > widget.worker.currentBalance) {
                                AppToast.show(AppLocalizations.of(context)!
                                    .insufficientBalanceForPurchase);
                                return;
                              }

                              setState(() => isLoading = true);

                              try {
                                final transactionProvider =
                                    Provider.of<TransactionProvider>(
                                  context,
                                  listen: false,
                                );
                                final authProvider = Provider.of<AuthProvider>(
                                  context,
                                  listen: false,
                                );

                                // Determine place: use custom input (populated by chips or user)
                                String? place =
                                    placeController.text.trim().isEmpty
                                        ? null
                                        : placeController.text.trim();

                                // Combine place and notes
                                String? combinedNotes;
                                if (place != null && place.isNotEmpty) {
                                  combinedNotes = AppLocalizations.of(context)!
                                      .locationPrefix(place);
                                  if (notesController.text.trim().isNotEmpty) {
                                    combinedNotes +=
                                        ' | ${notesController.text.trim()}';
                                  }
                                } else if (notesController.text
                                    .trim()
                                    .isNotEmpty) {
                                  combinedNotes = notesController.text.trim();
                                }

                                final success = await transactionProvider
                                    .recordCoffeePurchase(
                                  workerId: widget.worker.id,
                                  workerName: widget.worker.name,
                                  amount: totalAmount,
                                  createdBy: authProvider.getUserEmail() ??
                                      'Collector',
                                  notes: combinedNotes,
                                  coffeeType: selectedCoffeeType?.name,
                                  weight:
                                      double.tryParse(quantityController.text),
                                  pricePerKg:
                                      double.tryParse(priceController.text),
                                  commission: commissionAmount,
                                );

                                if (mounted) {
                                  Navigator.pop(context);
                                  widget.onSuccess();

                                  AppToast.show(
                                    success
                                        ? AppLocalizations.of(context)!
                                            .purchaseRecordedSuccess(
                                                AppLocalizations.of(context)?.currency ??
                                                    'ETB',
                                                commissionAmount.formatted)
                                        : AppLocalizations.of(context)!
                                            .failedToRecordPurchase,
                                    success: success,
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => isLoading = false);
                                  AppToast.show('Error: $e');
                                }
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.brown,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            AppLocalizations.of(context)!.recordPurchase,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAreaChip(String area, bool isDark) {
    final isSelected = placeController.text.trim() == area;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            placeController.clear();
          } else {
            placeController.text = area;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.brown.withOpacity(0.2)
              : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: Colors.brown) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on,
              size: 14,
              color: isSelected
                  ? Colors.brown
                  : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
            const SizedBox(width: 4),
            Text(
              area,
              style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? Colors.brown
                    : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
