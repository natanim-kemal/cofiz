import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'core/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/services/fcm_service.dart';
import 'core/services/area_service.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/audit_provider.dart';
import 'core/providers/worker_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/services/offline_sync_service.dart';
import 'core/services/notification_service.dart';
import 'core/providers/notification_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/providers/transaction_provider.dart';
import 'core/providers/income_provider.dart';
import 'core/providers/expense_provider.dart';
import 'core/services/income_service.dart';
import 'core/services/expense_service.dart';
import 'presentation/widgets/custom_bottom_nav.dart';
import 'presentation/widgets/offline_indicator.dart';
import 'presentation/widgets/double_back_exit.dart';
import 'presentation/widgets/app_toast.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/widgets/background_pattern.dart';
import 'presentation/screens/reports/reports_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/dashboard/dashboard_screen.dart';
import 'presentation/screens/worker_list/worker_list_screen.dart';
import 'presentation/screens/worker/worker_dashboard_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase already initialized, continue
    if (!e.toString().contains('duplicate-app')) {
      rethrow;
    }
  }

  // Register the FCM background handler early (cheap, local).
  FCMService().setup();

  // Fast, local-only initialization required before the first frame.
  final notificationService = NotificationService();
  await notificationService.initialize();

  // Initialize local caches (Hive) so the UI can read cached data immediately.
  final offlineSyncService = OfflineSyncService();
  await offlineSyncService.initialize();

  runApp(StitchWorkerApp(
    notificationService: notificationService,
    offlineSyncService: offlineSyncService,
  ));

  // Network-dependent initialization is deferred until after the first
  // frame so a slow connection doesn't hold up app startup. All calls run
  // in parallel.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _initializeNetworkServices();
  });
}

Future<void> _initializeNetworkServices() async {
  try {
    await Future.wait([
      FCMService().initialize(),
      AreaService().initializeDefaultAreas(),
      IncomeService().initializeDefaultSaleCategories(),
      ExpenseService().initializeDefaultExpenseCategories(),
    ]);
  } catch (e) {
    debugPrint('Background service initialization failed: $e');
  }
}

class StitchWorkerApp extends StatelessWidget {
  final NotificationService notificationService;
  final OfflineSyncService offlineSyncService;

  const StitchWorkerApp({
    super.key,
    required this.notificationService,
    required this.offlineSyncService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: notificationService),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => WorkerProvider()),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider(create: (_) => IncomeProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AuditProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: Consumer2<ThemeProvider, SettingsProvider>(
        builder: (context, themeProvider, settingsProvider, _) {
          return MaterialApp(
            title: 'Cofiz',
            // Locale
            locale: settingsProvider.locale,

            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            debugShowCheckedModeBanner: false,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('en'),
              Locale('am'),
            ],
            builder: (context, child) => ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: AppToastHost(child: child!),
            ),
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

/// Auth gate to check if user is logged in
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        if (authProvider.isAuthenticated && authProvider.user != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Provider.of<NotificationProvider>(context, listen: false)
                .init(authProvider.user!.uid);
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Provider.of<NotificationProvider>(context, listen: false)
                .disposeListener();
          });
        }
        // Show loading while checking auth state
        if (authProvider.status == AuthStatus.uninitialized) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Navigate based on auth status AND user role
        if (authProvider.isAuthenticated) {
          // Check if user role is loaded
          if (authProvider.userRole == null) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Account Not Set Up',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Your account has not been configured yet. Please contact an administrator to set up your account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await authProvider.signOut();
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign Out'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          // Route based on role
          switch (authProvider.userRole!) {
            case UserRole.admin:
              return MainLayout(key: MainLayout.mainLayoutKey);
            case UserRole.viewer:

              // Admin and Viewer use MainLayout
              // Viewer will have read-only restrictions in UI
              return MainLayout(key: MainLayout.mainLayoutKey);

            case UserRole.worker:

              // Workers go to their own dashboard
              if (authProvider.workerId != null) {
                return WorkerDashboardScreen(
                  workerId: authProvider.workerId!,
                );
              } else {
                return const Scaffold(
                  body: Center(
                    child: Text(
                        'Error: Collector account not properly configured'),
                  ),
                );
              }
          }
        }

        // Not authenticated - show login
        return const LoginScreen();
      },
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  static final GlobalKey<_MainLayoutState> mainLayoutKey =
      GlobalKey<_MainLayoutState>();

  static void navigateTo(int index) {
    mainLayoutKey.currentState?._onNavTap(index);
  }

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;
  late PageController _pageController;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const WorkerListScreen(),
    const ReportsScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _onNavTap(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DoubleBackExit(
      child: Scaffold(
        body: Stack(
          children: [
            const BackgroundPattern(),
            PageView(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              children: _screens,
            ),

            // Offline Indicator
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OfflineIndicator(),
            ),

            // Fixed Bottom Nav
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CustomBottomNav(
                currentIndex: _currentIndex,
                onTap: _onNavTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
