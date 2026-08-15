import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/worker_provider.dart';
import '../../../core/providers/transaction_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/worker_model.dart';
import '../../widgets/custom_header.dart';
import '../settings/settings_screen.dart';
import 'tabs/worker_home_tab.dart';
import 'tabs/worker_history_tab.dart';
import '../notifications/notifications_screen.dart';
import '../../widgets/background_pattern.dart';
import '../../widgets/notification_badge.dart';

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
  late PageController _pageController;
  Future<Worker?>? _workerFuture;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    // Load worker's transactions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TransactionProvider>(context, listen: false)
          .loadWorkerTransactions(widget.workerId);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final workerProvider = Provider.of<WorkerProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FutureBuilder<Worker?>(
      future: _workerFuture ??=
          workerProvider.getWorkerById(widget.workerId),
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

        return Scaffold(
          body: Stack(
            children: [
              const BackgroundPattern(),
              Column(
                children: [
                  // Hide header on Settings screen to avoid double headers
                  if (_currentIndex != 2)
                    CustomHeader(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppLocalizations.of(context)!.welcomeBack,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    worker.name,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: IconButton(
                                      icon: const Icon(Icons.refresh,
                                          color: Colors.white),
                                      tooltip:
                                          AppLocalizations.of(context)!.refresh,
                                      onPressed: () => setState(() {}),
                                    ),
                                  ),
                                  NotificationBadge(
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.notifications_outlined,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                      tooltip: AppLocalizations.of(context)!
                                          .notifications,
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const NotificationsScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            DateFormat('EEEE, MMMM d, yyyy')
                                .format(DateTime.now()),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: _onPageChanged,
                      children: [
                        WorkerHomeTab(
                          worker: worker,
                          isDark: isDark,
                          onRefresh: () {
                            setState(() {});
                            Provider.of<TransactionProvider>(context,
                                    listen: false)
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
                  ),
                ],
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onNavTap,
            selectedItemColor: AppColors.primary,
            selectedFontSize: 10,
            unselectedFontSize: 10,
            iconSize: 24,
            items: [
              BottomNavigationBarItem(
                icon: const Icon(
                    Icons.grid_view_rounded), // Uniform with Admin Dashboard
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
        );
      },
    );
  }
}
