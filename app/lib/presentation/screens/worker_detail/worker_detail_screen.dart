import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/worker_model.dart';
import '../../../core/providers/worker_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/audit_provider.dart';
import '../../../core/providers/notification_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_formatter.dart';
import '../../../core/utils/worker_actions.dart';
import '../worker_form/worker_form_screen.dart';
import '../transaction/transaction_dialog.dart';
import '../transaction/transfer_dialog.dart';
import '../../dialogs/ping_dialog.dart';
import '../../widgets/worker_picker_sheet.dart';
import '../../widgets/worker_transactions_list.dart';
import '../../widgets/background_pattern.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';

class WorkerDetailScreen extends StatelessWidget {
  final String workerId;

  const WorkerDetailScreen({super.key, required this.workerId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: AppColors.backgroundLight, // Removed for theme support
      body: Stack(
        children: [
          const BackgroundPattern(),
          Consumer<WorkerProvider>(
            builder: (context, workerProvider, _) {
              // Find worker from the reactive list (using full list)
              final worker = workerProvider.findById(workerId);

              if (worker == null) {
                // If not found in list, try fetching it (or show loading/error)
                if (workerProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: AppColors.primary),
                      const SizedBox(height: 16),
                      Text(AppLocalizations.of(context)!.workerNotFound),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(AppLocalizations.of(context)!.goBack),
                      ),
                    ],
                  ),
                );
              }

              return CustomScrollView(
                slivers: [
                  // App Bar
                  SliverAppBar(
                    expandedHeight: 120,
                    floating: false,
                    pinned: true,
                    backgroundColor: AppColors.primary,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    actions: [
                      Consumer<AuthProvider>(
                        builder: (context, authProvider, _) {
                          final canEdit =
                              authProvider.userRole?.canEditWorkers ?? false;
                          final canDelete =
                              authProvider.userRole?.canDeleteWorkers ?? false;

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canEdit) ...[
                                if (worker.userId != null)
                                  IconButton(
                                    icon: Transform.rotate(
                                      angle: -0.35,
                                      child: const Icon(Icons.send,
                                          color: Colors.white),
                                    ),
                                    tooltip: AppLocalizations.of(context)!
                                        .pingWorker,
                                    onPressed: () => _showPingDialog(
                                        context, worker, authProvider),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.white),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            WorkerFormScreen(worker: worker),
                                      ),
                                    );
                                  },
                                ),
                              ],
                              if (canDelete)
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.white),
                                  onPressed: () async {
                                    final confirmed = await WorkerActions
                                        .showDeleteConfirmation(
                                      context,
                                      worker.name,
                                    );

                                    if (confirmed == true && context.mounted) {
                                      final workerProvider =
                                          Provider.of<WorkerProvider>(
                                        context,
                                        listen: false,
                                      );
                                      final success = await workerProvider
                                          .deleteWorker(worker.id);

                                      if (context.mounted) {
                                        if (success) {
                                          final authProvider =
                                              Provider.of<AuthProvider>(
                                            context,
                                            listen: false,
                                          );
                                          final auditProvider =
                                              Provider.of<AuditProvider>(
                                            context,
                                            listen: false,
                                          );
                                          await auditProvider.logWorkerDeleted(
                                            userId: authProvider.user?.uid ??
                                                'unknown',
                                            userName: authProvider
                                                    .appUser?.displayName ??
                                                authProvider.user?.email ??
                                                'admin',
                                            workerId: worker.id,
                                            workerName: worker.name,
                                          );
                                          Navigator.pop(context);
                                          AppToast.show(
                                              AppLocalizations.of(context)!
                                                  .workerDeletedSuccessfully,
                                              success: true);
                                        } else {
                                          AppToast.show(
                                              workerProvider.errorMessage ??
                                                  AppLocalizations.of(context)!
                                                      .failedToDeleteWorker);
                                        }
                                      }
                                    }
                                  },
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      title: Text(
                        worker.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      background: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withOpacity(0.8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Content
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Profile Card
                          _buildProfileCard(context, worker),

                          const SizedBox(height: 20),

                          // Balance Card
                          _buildBalanceCard(context, worker),

                          const SizedBox(height: 20),

                          // Action Buttons
                          _buildActionButtons(context, worker),

                          const SizedBox(height: 40),

                          // Worker Transactions List (renders its own header + filter)
                          WorkerTransactionsList(
                            workerId: workerId,
                            worker: worker,
                          ),

                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, Worker worker) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
                Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.contactDetails,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (worker.phone.isNotEmpty)
                      _buildInfoRow(context, Icons.phone, worker.phone),
                    if (worker.email != null && worker.email!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildInfoRow(context, Icons.email, worker.email!),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(
                      context,
                      Icons.work_history,
                      AppLocalizations.of(context)!
                          .yearsExperience('${worker.yearsOfExperience}'),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      context,
                      Icons.paid,
                      AppLocalizations.of(context)!.commissionRateInfo(
                        AppLocalizations.of(context)?.currency ?? 'ETB',
                        worker.commissionRate.toStringAsFixed(2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Call/SMS Actions
          if (worker.phone.isNotEmpty) ...[
            const SizedBox(height: 20),
            Divider(color: Colors.grey.shade200),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await WorkerActions.sendSMS(worker.phone);
                      } catch (e) {
                        if (context.mounted) {
                          AppToast.show(AppLocalizations.of(context)!
                              .couldNotSendSMS(e.toString()));
                        }
                      }
                    },
                    icon: const Icon(Icons.message, size: 18),
                    label: Text(AppLocalizations.of(context)!.message),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await WorkerActions.makePhoneCall(worker.phone);
                      } catch (e) {
                        if (context.mounted) {
                          AppToast.show(AppLocalizations.of(context)!
                              .couldNotMakeCall(e.toString()));
                        }
                      }
                    },
                    icon: const Icon(Icons.phone, size: 18),
                    label: Text(AppLocalizations.of(context)!.call),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatarInitials(String name) {
    return Center(
      child: Text(
        name.substring(0, 2).toUpperCase(),
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: 32,
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard(BuildContext context, Worker worker) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primary.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.currentBalance,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${AppLocalizations.of(context)?.currency ?? 'ETB'} ${worker.currentBalance.formatted}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildBalanceItem(
                  AppLocalizations.of(context)!.distributed,
                  '${AppLocalizations.of(context)?.currency ?? 'ETB'} ${worker.totalDistributed.formatted}',
                  Icons.arrow_downward,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white24,
              ),
              Expanded(
                child: _buildBalanceItem(
                  AppLocalizations.of(context)!.returned,
                  '${AppLocalizations.of(context)?.currency ?? 'ETB'} ${worker.totalReturned.formatted}',
                  Icons.arrow_upward,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 1,
            color: Colors.white24,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildBalanceItem(
                  AppLocalizations.of(context)!.purchased,
                  '${AppLocalizations.of(context)?.currency ?? 'ETB'} ${worker.totalCoffeePurchased.formatted}',
                  Icons.shopping_cart,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white24,
              ),
              Expanded(
                child: _buildBalanceItem(
                  AppLocalizations.of(context)!.commission,
                  '${AppLocalizations.of(context)?.currency ?? 'ETB'} ${worker.totalCommissionEarned.formatted}',
                  Icons.paid,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, Worker worker) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final canCreateTransactions =
            authProvider.userRole?.canCreateTransactions ?? false;

        // Don't show action buttons if user can't create transactions (viewers)
        if (!canCreateTransactions) {
          return const SizedBox.shrink();
        }

        return Row(
          children: [
            Expanded(
              child: _buildActionButton(
                context,
                AppLocalizations.of(context)!.distribute,
                Icons.add_circle,
                () async {
                  final result = await showDialog<bool>(
                    context: context,
                    builder: (context) => TransactionDialog(
                      worker: worker,
                      type: 'distribution',
                    ),
                  );
                  if (result == true) {
                    // Refresh worker data
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                context,
                AppLocalizations.of(context)!.purchase,
                Icons.shopping_cart,
                () async {
                  final result = await showDialog<bool>(
                    context: context,
                    builder: (context) => TransactionDialog(
                      worker: worker,
                      type: 'purchase',
                    ),
                  );
                  if (result == true) {
                    // Refresh worker data
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                context,
                AppLocalizations.of(context)!.transfer,
                Icons.swap_horiz,
                () async {
                  final workerProvider =
                      Provider.of<WorkerProvider>(context, listen: false);
                  final workers = workerProvider.workers
                      .where((w) => w.isActive && w.id != worker.id)
                      .toList();
                  if (workers.isEmpty) {
                    AppToast.show('No collectors available');
                    return;
                  }

                  final receiver = await showModalBottomSheet<Worker>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => WorkerPickerSheet(
                      workers: workers,
                      mode: 'transfer_receiver',
                      exclude: worker,
                    ),
                  );
                  if (receiver == null || !context.mounted) return;

                  await showDialog<bool>(
                    context: context,
                    builder: (context) =>
                        TransferDialog(sender: worker, receiver: receiver),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) {
    const warmOrange = AppColors.primary;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: warmOrange.withOpacity(
            Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.12),
        foregroundColor: warmOrange,
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'busy':
        return Colors.orange;
      case 'offline':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Future<void> _showPingDialog(
      BuildContext context, Worker worker, AuthProvider authProvider) async {
    await showDialog(
      context: context,
      builder: (context) => PingDialog(
        title: AppLocalizations.of(context)!.pingWorkerTitle(worker.name),
        messageLabel: AppLocalizations.of(context)!.message,
        onSend: (message) async {
          final notificationProvider =
              Provider.of<NotificationProvider>(context, listen: false);

          await notificationProvider.sendPing(
            targetUserId: worker.userId!,
            title: AppLocalizations.of(context)!.messageFromAdmin,
            body: message,
            senderName: authProvider.user?.displayName ??
                AppLocalizations.of(context)!.admin,
            senderId: authProvider.user?.uid ?? '',
          );

          if (context.mounted) {
            AppToast.show(AppLocalizations.of(context)!
                .notificationSentToUser(worker.name));
          }
        },
      ),
    );
  }
}
