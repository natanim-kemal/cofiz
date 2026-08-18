import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/worker_provider.dart';
import '../../../core/providers/transaction_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/worker_model.dart';
import '../settings/settings_screen.dart';
import 'tabs/worker_home_tab.dart';
import 'tabs/worker_history_tab.dart';
import '../../widgets/background_pattern.dart';
import '../../widgets/double_back_exit.dart';

class WorkerDashboardScreen extends StatefulWidget {
  final String workerId;

  const WorkerDashboardScreen({
    super.key,
    required this.workerId,
  });

  @override
  State<WorkerDashboardScreen> createState() => _WorkerDashboardScreenState();
}

class _WorkerDashboardScreenState extends State<WorkerDashboardScreen> {
  int _currentIndex = 0;
  Future<Worker?>? _workerFuture;

  @override
  void initState() {
    super.initState();
    // Load worker's transactions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TransactionProvider>(context, listen: false)
          .loadWorkerTransactions(widget.workerId);
    });
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final workerProvider = Provider.of<WorkerProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FutureBuilder<Worker?>(
      future: _workerFuture ??= workerProvider.getWorkerById(widget.workerId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(AppLocalizations.of(context)!.workerDataNotFound),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => authProvider.signOut(),
                    child: Text(AppLocalizations.of(context)!.signOut),
                  ),
                ],
              ),
            ),
          );
        }

        final worker = snapshot.data!;

        return DoubleBackExit(
          child: Scaffold(
            body: Stack(
              children: [
                const BackgroundPattern(),
                IndexedStack(
                  index: _currentIndex,
                  children: [
                    WorkerHomeTab(
                      worker: worker,
                      isDark: isDark,
                      onRefresh: () async {
                        setState(() {
                          _workerFuture =
                              workerProvider.getWorkerById(widget.workerId);
                        });
                        Provider.of<TransactionProvider>(context, listen: false)
                            .loadWorkerTransactions(widget.workerId);
                      },
                      onViewHistory: () => _onNavTap(1),
                    ),
                    WorkerHistoryTab(
                        worker: worker,
                        isDark: isDark,
                        onRefresh: () {
                          Provider.of<TransactionProvider>(context,
                                  listen: false)
                              .loadWorkerTransactions(widget.workerId);
                        }),
                    const SettingsScreen(),
                  ],
                ),
              ],
            ),
            bottomNavigationBar: Theme(
              data: Theme.of(context).copyWith(
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
              ),
              child: BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: _onNavTap,
                selectedItemColor: AppColors.primary,
                selectedFontSize: 10,
                unselectedFontSize: 10,
                iconSize: 24,
                items: [
                  BottomNavigationBarItem(
                    icon: const Icon(Icons
                        .grid_view_rounded), // Uniform with Admin Dashboard
                    label: AppLocalizations.of(context)!.navHome,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.history),
                    label: AppLocalizations.of(context)!.navHistory,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(
                        Icons.settings_outlined), // Uniform with Admin Settings
                    label: AppLocalizations.of(context)!.navSettings,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
