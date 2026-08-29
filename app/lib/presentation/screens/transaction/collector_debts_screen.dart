import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/debt_model.dart';
import '../../../core/services/debt_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';

class CollectorDebtsScreen extends StatelessWidget {
  const CollectorDebtsScreen({super.key, required this.collectorId, required this.collectorName});
  final String collectorId;
  final String collectorName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final debtService = DebtService();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('${l10n.collector} • $collectorName'),
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<List<Debt>>(
        stream: debtService.streamDebtsForCollector(collectorId),
        builder: (context, snap) {
          final debts = snap.data ?? const <Debt>[];
          final open = debts.where((d) => d.status == DebtStatus.open).toList();
          final paid = debts.where((d) => d.status == DebtStatus.paid).toList();
          final openTotal = open.fold<double>(0, (a, d) => a + d.forgivenAmount);

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat(value: 'ETB ${openTotal.toStringAsFixed(0)}', label: l10n.pending, color: AppColors.error),
                    Container(width: 1, height: 36, color: isDark ? Colors.white12 : Colors.black12),
                    _Stat(value: '${open.length}', label: l10n.pending),
                    _Stat(value: '${paid.length}', label: l10n.done),
                  ],
                ),
              ),
              Expanded(
                child: debts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 32),
                            ),
                            const SizedBox(height: 16),
                            Text('No debts recorded.', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text('Debts will appear here when a purchase exceeds balance.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: debts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final d = debts[i];
                          final isOpen = d.status == DebtStatus.open;
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.surfaceDark : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: (isOpen ? AppColors.error : AppColors.success).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(isOpen ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                                      color: isOpen ? AppColors.error : AppColors.success),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('ETB ${d.totalAmount.toStringAsFixed(0)} • forgiven ${d.forgivenAmount.toStringAsFixed(0)}',
                                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                      Text(DateFormat.yMMMd().format(d.createdAt),
                                          style: theme.textTheme.bodySmall?.copyWith(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isOpen ? AppColors.error.withOpacity(0.12) : AppColors.success.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(d.status.name.toUpperCase(),
                                      style: theme.textTheme.labelSmall?.copyWith(
                                          color: isOpen ? AppColors.error : AppColors.success, fontWeight: FontWeight.w700, fontSize: 11)),
                                ),
                                if (isOpen) ...[
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    height: 32,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text('Mark as paid?'),
                                            content: Text('Collector $collectorName paid ETB ${d.forgivenAmount.toStringAsFixed(0)}?'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
                                              ElevatedButton(
                                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                                                  onPressed: () => Navigator.pop(context, true),
                                                  child: const Text('Confirm')),
                                            ],
                                          ),
                                        );
                                        if (ok == true) await DebtService().markPaid(d.id);
                                      },
                                      child: const Text('Paid', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});
  final String value;
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color ?? Theme.of(context).textTheme.titleMedium?.color)),
      Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMutedLight, fontWeight: FontWeight.w600)),
    ]);
  }
}
