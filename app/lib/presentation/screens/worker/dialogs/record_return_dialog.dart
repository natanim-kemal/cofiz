import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/models/worker_model.dart';
import '../../../../core/utils/number_formatter.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/transaction_provider.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../widgets/app_toast.dart';

class RecordReturnDialog extends StatefulWidget {
  final Worker worker;
  final VoidCallback onSuccess;

  const RecordReturnDialog({
    super.key,
    required this.worker,
    required this.onSuccess,
  });

  @override
  State<RecordReturnDialog> createState() => _RecordReturnDialogState();
}

class _RecordReturnDialogState extends State<RecordReturnDialog> {
  final amountController = TextEditingController();
  final notesController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool isLoading = false;

  @override
  void dispose() {
    amountController.dispose();
    notesController.dispose();
    super.dispose();
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
                  const Icon(Icons.arrow_upward, color: Colors.green, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)!.returnMoneyTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.recordReturnSubtitle,
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),

              // Amount field
              TextFormField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.amountLabel(
                      AppLocalizations.of(context)?.currency ?? 'ETB'),
                  prefixIcon: const Icon(Icons.attach_money),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor:
                      isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return AppLocalizations.of(context)!.pleaseEnterAmount;
                  }
                  final amount = double.tryParse(value);
                  if (amount == null || amount <= 0) {
                    return AppLocalizations.of(context)!.pleaseEnterValidAmount;
                  }
                  if (amount > widget.worker.currentBalance) {
                    return AppLocalizations.of(context)!.amountExceedsBalance;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Notes field
              TextFormField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.notesOptional,
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
              const SizedBox(height: 24),

              // Current balance info
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
                    Text(
                      AppLocalizations.of(context)!.currentBalanceInfo(
                          AppLocalizations.of(context)?.currency ?? 'ETB',
                          widget.worker.currentBalance.formatted),
                      style: const TextStyle(color: Colors.blue),
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

                              final success = await transactionProvider
                                  .returnMoneyFromWorker(
                                workerId: widget.worker.id,
                                workerName: widget.worker.name,
                                amount: double.parse(amountController.text),
                                createdBy:
                                    authProvider.getUserEmail() ?? 'Collector',
                                notes: notesController.text.isEmpty
                                    ? null
                                    : notesController.text,
                              );

                              if (mounted) {
                                Navigator.pop(context);
                                widget.onSuccess();

                                AppToast.show(
                                  success
                                      ? AppLocalizations.of(context)!
                                          .returnRecordedSuccess
                                      : AppLocalizations.of(context)!
                                          .failedToRecordReturn,
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
                    backgroundColor: Colors.green,
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
                          AppLocalizations.of(context)!.recordReturn,
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
    );
  }
}
