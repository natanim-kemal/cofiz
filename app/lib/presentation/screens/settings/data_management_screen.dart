import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/providers/worker_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/audit_provider.dart';
import '../../../core/providers/transaction_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  bool _isLoading = false;

  Future<void> _exportData() async {
    setState(() => _isLoading = true);
    try {
      final workerProvider =
          Provider.of<WorkerProvider>(context, listen: false);
      final transactionProvider =
          Provider.of<TransactionProvider>(context, listen: false);

      final data = {
        'timestamp': DateTime.now().toIso8601String(),
        'version': '1.0.0',
        'stats': {
          'total_workers': workerProvider.workers.length,
          'total_transactions': transactionProvider.allTransactions.length,
        },
        'workers': workerProvider.workers.map((w) => w.toJson()).toList(),
        'transactions':
            transactionProvider.allTransactions.map((t) => t.toJson()).toList(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'cofiz_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonString);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final auditProvider = Provider.of<AuditProvider>(context, listen: false);
      await auditProvider.logDataExported(
        userId: authProvider.user?.uid ?? 'unknown',
        userName:
            authProvider.appUser?.displayName ?? authProvider.user?.email ?? '',
        exportType: 'json',
        recordCount: workerProvider.workers.length +
            transactionProvider.allTransactions.length,
      );

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.backupSuccessful),
            content:
                Text(AppLocalizations.of(context)!.dataExportedTo(file.path)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.ok),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(AppLocalizations.of(context)!.exportFailed('e'));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.clearCache),
        content: Text(AppLocalizations.of(context)!.clearCacheConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.clear,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();

        if (mounted) {
          AppToast.show(
            AppLocalizations.of(context)!.cacheCleared,
            success: true,
          );
        }
      } catch (e) {
        if (mounted) {
          AppToast.show('Error: $e');
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.dataManagement),
        backgroundColor: theme.appBarTheme.backgroundColor ?? AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
                context, AppLocalizations.of(context)!.backupAndExport),
            const SizedBox(height: 16),
            _buildActionTile(
              context,
              icon: Icons.download_rounded,
              title: AppLocalizations.of(context)!.exportDataJson,
              subtitle: AppLocalizations.of(context)!.exportDataSubtitle,
              onTap: _exportData,
            ),
            const SizedBox(height: 32),
            _buildSectionHeader(context, AppLocalizations.of(context)!.storage),
            const SizedBox(height: 16),
            _buildActionTile(
              context,
              icon: Icons.cleaning_services_outlined,
              title: AppLocalizations.of(context)!.clearAppCache,
              subtitle: AppLocalizations.of(context)!.clearAppCacheSubtitle,
              isDestructive: true,
              onTap: _clearCache,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color =
        isDestructive ? Colors.red : (isDark ? Colors.white : Colors.black87);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: _isLoading ? null : onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                icon,
                color: AppColors.primary,
                size: 28,
              ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.primary),
      ),
    );
  }
}
