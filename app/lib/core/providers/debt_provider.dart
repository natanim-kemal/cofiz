import 'package:flutter/foundation.dart';
import '../models/debt_model.dart';
import '../services/debt_service.dart';
import '../services/notification_trigger_service.dart';

class DebtProvider extends ChangeNotifier {
  DebtProvider({required this.debtService, required this.notificationService});
  final DebtService debtService;
  final NotificationTriggerService notificationService;

  Map<String, List<Debt>> byCollector = {};
  double openTotal = 0;
  double todayOpenTotal = 0;
  Map<String, int> openCountByCollector = {};

  Future<Debt> recordDebtFromPurchase({
    required String collectorId,
    required String collectorName,
    required String purchaseId,
    required double totalAmount,
    required double coveredAmount,
    required double forgivenAmount,
    required String createdBy,
    String? notes,
  }) async {
    final debt = await debtService.createDebtFromPurchase(
      collectorId: collectorId,
      collectorName: collectorName,
      purchaseId: purchaseId,
      totalAmount: totalAmount,
      coveredAmount: coveredAmount,
      forgivenAmount: forgivenAmount,
      createdBy: createdBy,
      notes: notes,
    );
    try {
      await notificationService.notifyDebtRecorded(
        collectorId: collectorId,
        collectorName: collectorName,
        forgivenAmount: forgivenAmount,
        totalAmount: totalAmount,
      );
    } catch (_) {}
    await refreshTotals();
    notifyListeners();
    return debt;
  }

  Future<void> markPaid(String debtId) async {
    await debtService.markPaid(debtId);
    await refreshTotals();
    notifyListeners();
  }

  Future<void> refreshTotals() async {
    openTotal = await debtService.getOpenDebtsTotal();
    todayOpenTotal = await debtService.getOpenDebtsTotalForToday();
  }

  void updateCounts(List<Debt> allOpen) {
    final map = <String, int>{};
    for (final d in allOpen) {
      map[d.collectorId] = (map[d.collectorId] ?? 0) + 1;
    }
    openCountByCollector = map;
    // group by collector for byCollector
    final grouped = <String, List<Debt>>{};
    for (final d in allOpen) {
      grouped.putIfAbsent(d.collectorId, () => []).add(d);
    }
    byCollector = grouped;
    notifyListeners();
  }
}
