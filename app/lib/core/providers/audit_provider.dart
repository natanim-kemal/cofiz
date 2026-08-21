import 'package:flutter/foundation.dart';
import '../models/audit_log_model.dart';
import '../services/audit_service.dart';

class AuditProvider with ChangeNotifier {
  final AuditService _auditService = AuditService();

  /// Log worker creation
  Future<void> logWorkerCreated({
    required String userId,
    required String userName,
    required String workerId,
    required String workerName,
    bool hasLoginAccount = false,
  }) async {
    await _auditService.log(
      userId: userId,
      userName: userName,
      action: AuditAction.workerCreated,
      targetId: workerId,
      targetName: workerName,
      metadata: {
        'hasLoginAccount': hasLoginAccount,
      },
    );
  }

  /// Log worker update
  Future<void> logWorkerUpdated({
    required String userId,
    required String userName,
    required String workerId,
    required String workerName,
    Map<String, dynamic>? changes,
  }) async {
    await _auditService.log(
      userId: userId,
      userName: userName,
      action: AuditAction.workerUpdated,
      targetId: workerId,
      targetName: workerName,
      metadata: changes,
    );
  }

  /// Log worker deletion
  Future<void> logWorkerDeleted({
    required String userId,
    required String userName,
    required String workerId,
    required String workerName,
  }) async {
    await _auditService.log(
      userId: userId,
      userName: userName,
      action: AuditAction.workerDeleted,
      targetId: workerId,
      targetName: workerName,
    );
  }

  /// Log transaction creation
  Future<void> logTransactionCreated({
    required String userId,
    required String userName,
    required String transactionId,
    required String transactionType,
    required double amount,
    required String workerName,
  }) async {
    await _auditService.log(
      userId: userId,
      userName: userName,
      action: AuditAction.transactionCreated,
      targetId: transactionId,
      targetName: workerName,
      metadata: {
        'type': transactionType,
        'amount': amount,
      },
    );
  }

  /// Log user login
  Future<void> logLogin({
    required String userId,
    required String userName,
  }) async {
    await _auditService.log(
      userId: userId,
      userName: userName,
      action: AuditAction.login,
    );
  }

  /// Log user logout
  Future<void> logLogout({
    required String userId,
    required String userName,
  }) async {
    await _auditService.log(
      userId: userId,
      userName: userName,
      action: AuditAction.logout,
    );
  }

  /// Log transaction deletion
  Future<void> logTransactionDeleted({
    required String userId,
    required String userName,
    required String transactionId,
    required String transactionType,
    required double amount,
    required String workerName,
    bool wasUnconfirmed = false,
    String? reason,
  }) async {
    await _auditService.log(
      userId: userId,
      userName: userName,
      action: AuditAction.transactionDeleted,
      targetId: transactionId,
      targetName: workerName,
      metadata: {
        'type': transactionType,
        'amount': amount,
        'wasUnconfirmed': wasUnconfirmed,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
  }

  /// Log transaction update
  Future<void> logTransactionUpdated({
    required String userId,
    required String userName,
    required String transactionId,
    required String transactionType,
    required double amount,
    required String workerName,
    String? reason,
    Map<String, dynamic>? changes,
  }) async {
    await _auditService.log(
      userId: userId,
      userName: userName,
      action: AuditAction.transactionUpdated,
      targetId: transactionId,
      targetName: workerName,
      metadata: {
        'type': transactionType,
        'amount': amount,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (changes != null) 'changes': changes,
      },
    );
  }

  /// Log user account creation (for workers with login)
  Future<void> logUserCreated({
    required String adminUserId,
    required String adminUserName,
    required String newUserId,
    required String newUserEmail,
    required String role,
  }) async {
    await _auditService.log(
      userId: adminUserId,
      userName: adminUserName,
      action: AuditAction.userCreated,
      targetId: newUserId,
      targetName: newUserEmail,
      metadata: {
        'role': role,
      },
    );
  }

  /// Log user profile update
  Future<void> logUserUpdated({
    required String userId,
    required String userName,
    Map<String, dynamic>? changes,
  }) async {
    await _auditService.log(
      userId: userId,
      userName: userName,
      action: AuditAction.userUpdated,
      metadata: changes,
    );
  }

  /// Log data export
  Future<void> logDataExported({
    required String userId,
    required String userName,
    required String exportType,
    int? recordCount,
  }) async {
    await _auditService.log(
      userId: userId,
      userName: userName,
      action: AuditAction.dataExported,
      metadata: {
        'exportType': exportType,
        if (recordCount != null) 'recordCount': recordCount,
      },
    );
  }

  /// Log income recording
  Future<void> logIncomeRecorded({
    required String userId,
    required String userName,
    required String incomeId,
    required String kind,
    required double amount,
  }) async {
    await _auditService.log(
      userId: userId,
      userName: userName,
      action: AuditAction.incomeRecorded,
      targetId: incomeId,
      metadata: {
        'kind': kind,
        'amount': amount,
      },
    );
  }

  /// Log expense recording
  Future<void> logExpenseRecorded({
    required String userId,
    required String userName,
    required String expenseId,
    required String category,
    required double amount,
  }) async {
    await _auditService.log(
      userId: userId,
      userName: userName,
      action: AuditAction.expenseRecorded,
      targetId: expenseId,
      metadata: {
        'category': category,
        'amount': amount,
      },
    );
  }

  /// Log settings change
  Future<void> logSettingsChanged({
    required String userId,
    required String userName,
    required String setting,
    String? oldValue,
    String? newValue,
  }) async {
    await _auditService.log(
      userId: userId,
      userName: userName,
      action: AuditAction.settingsChanged,
      metadata: {
        'setting': setting,
        if (oldValue != null) 'oldValue': oldValue,
        if (newValue != null) 'newValue': newValue,
      },
    );
  }
}
