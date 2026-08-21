import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/models/audit_log_model.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/background_pattern.dart';
import '../../../l10n/app_localizations.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final AuditService _auditService = AuditService();
  AuditAction? _selectedFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context);

    // Only admins can view audit logs
    if (authProvider.userRole?.canManageUsers != true) {
      return Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.auditLogs),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: Stack(
          children: [
            const BackgroundPattern(),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.accessDenied,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.adminAuditLogsOnly,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Logs'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<AuditAction?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter',
            onSelected: (value) {
              setState(() => _selectedFilter = value);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: null,
                child: Text(AppLocalizations.of(context)!.allActions),
              ),
              const PopupMenuDivider(),
              ...AuditAction.values.map((action) => PopupMenuItem(
                    value: action,
                    child: Row(
                      children: [
                        Icon(
                          _getActionIcon(action),
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(action.displayName),
                      ],
                    ),
                  )),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          const BackgroundPattern(),
          Column(
            children: [
              // Filter indicator
              if (_selectedFilter != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                  child: Row(
                    children: [
                      Icon(
                        _getActionIcon(_selectedFilter!),
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context)!
                            .filtering(_selectedFilter!.displayName),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _selectedFilter = null),
                        child: Text(AppLocalizations.of(context)!.clear),
                      ),
                    ],
                  ),
                ),

              // Logs list
              Expanded(
                child: StreamBuilder<List<AuditLog>>(
                  stream: _selectedFilter != null
                      ? _auditService.getActionLogsStream(_selectedFilter!,
                          limit: 100)
                      : _auditService.getLogsStream(limit: 100),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline,
                                size: 48, color: AppColors.primary),
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context)!.errorLoadingLogs,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              snapshot.error.toString(),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }

                    final logs = snapshot.data ?? [];

                    if (logs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history,
                              size: 64,
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context)!.noAuditLogs,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(context)!
                                  .activityLogsWillAppear,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      );
                    }

                    // Group logs by date
                    final groupedLogs = <String, List<AuditLog>>{};
                    for (final log in logs) {
                      final dateKey =
                          DateFormat('MMMM d, yyyy').format(log.timestamp);
                      groupedLogs.putIfAbsent(dateKey, () => []).add(log);
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: groupedLogs.length,
                      itemBuilder: (context, index) {
                        final dateKey = groupedLogs.keys.elementAt(index);
                        final dayLogs = groupedLogs[dateKey]!;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                dateKey,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                            ...dayLogs.map((log) => _buildLogTile(log, isDark)),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogTile(AuditLog log, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action icon
          Icon(
            _getActionIcon(log.action),
            color: AppColors.primary,
            size: 24,
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.formattedMessage,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('h:mm a').format(log.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                ),
                if (log.metadata != null && log.metadata!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: log.metadata!.entries.take(3).map((entry) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${entry.key}: ${entry.value}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.grey.shade300
                                : Colors.grey.shade700,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getActionIcon(AuditAction action) {
    switch (action) {
      case AuditAction.userCreated:
        return Icons.person_add;
      case AuditAction.userUpdated:
        return Icons.person;
      case AuditAction.userDeleted:
        return Icons.person_remove;
      case AuditAction.userRoleChanged:
        return Icons.admin_panel_settings;
      case AuditAction.workerCreated:
        return Icons.person_add_alt;
      case AuditAction.workerUpdated:
        return Icons.edit;
      case AuditAction.workerDeleted:
        return Icons.delete;
      case AuditAction.transactionCreated:
        return Icons.attach_money;
      case AuditAction.transactionDeleted:
        return Icons.delete_forever;
      case AuditAction.transactionUpdated:
        return Icons.edit;
      case AuditAction.incomeRecorded:
        return Icons.trending_up;
      case AuditAction.expenseRecorded:
        return Icons.receipt_long;
      case AuditAction.settingsChanged:
        return Icons.settings;
      case AuditAction.dataExported:
        return Icons.download;
      case AuditAction.dataImported:
        return Icons.upload;
      case AuditAction.login:
        return Icons.login;
      case AuditAction.logout:
        return Icons.logout;
    }
  }

  Color _getActionColor(AuditAction action) {
    return AppColors.primary;
  }
}
