import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'core/models/user_model.dart';
import 'core/config/relay_config.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/services/fcm_service.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/density_provider.dart';
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
import 'core/services/auth_backend.dart';
import 'core/services/auth_backend_firebase.dart';
import 'core/providers/phone_otp_auth_provider.dart';
import 'core/services/pin_service.dart';
import 'core/providers/lock_state_provider.dart';
import 'core/services/idle_lock_service.dart';
import 'core/services/debt_service.dart';
import 'core/providers/debt_provider.dart';
import 'core/services/notification_trigger_service.dart';
import 'presentation/screens/auth/create_pin_screen.dart';
import 'presentation/screens/auth/pin_lock_screen.dart';
import 'presentation/widgets/custom_bottom_nav.dart';
import 'presentation/widgets/offline_indicator.dart';
import 'presentation/widgets/double_back_exit.dart';
import 'presentation/widgets/app_toast.dart';
import 'presentation/widgets/animated_splash_screen.dart';
import 'presentation/widgets/telegram_login_listener.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/widgets/background_pattern.dart';
import 'presentation/screens/reports/reports_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/dashboard/dashboard_screen.dart';
import 'presentation/screens/worker_list/worker_list_screen.dart';
import 'presentation/screens/worker/worker_dashboard_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Bottom-nav taps between adjacent tabs slide smoothly; taps that skip over
/// a tab jump directly instead of scrolling across the intermediate pages
/// (which are built lazily and cause the janky, sticky feel).
bool shouldAnimateTabSwitch(int from, int to) => (to - from).abs() == 1;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('[main] initializing Firebase...');
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
  debugPrint('[main] Firebase ready');

  // Register the FCM background handler early (cheap, local).
  FCMService().setup();

  // Fast, local-only initialization required before the first frame.
  final notificationService = NotificationService();
  debugPrint('[main] initializing NotificationService...');
  await notificationService.initialize();
  debugPrint('[main] NotificationService ready');

  // Initialize local caches (Hive) so the UI can read cached data immediately.
  final offlineSyncService = OfflineSyncService();
  debugPrint('[main] initializing OfflineSyncService...');
  await offlineSyncService.initialize();
  debugPrint('[main] OfflineSyncService ready');

  debugPrint('[main] runApp');
  runApp(StitchWorkerApp(
    notificationService: notificationService,
    offlineSyncService: offlineSyncService,
  ));
  debugPrint('[main] first frame scheduled; network services deferred');

  // Network-dependent initialization is deferred until after the first
  // frame so a slow connection doesn't hold up app startup. All calls run
  // in parallel. RelayConfig is initialized here so Firestore-sourced
  // relayUrl/relaySecret are available without --dart-define.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _initializeNetworkServices();
  });
}

Future<void> _initializeNetworkServices() async {
  try {
    await Future.wait([
      FCMService().initialize(),
      IncomeService().initializeDefaultSaleCategories(),
      ExpenseService().initializeDefaultExpenseCategories(),
      RelayConfig.init(),
    ]);
  } catch (e) {
    debugPrint('Background service initialization failed: $e');
  }
  // Ensure RelayConfig attempted even if other services failed
  try {
    await RelayConfig.ensureInitialized();
  } catch (e) {
    debugPrint('[RelayConfig] post-init ensure failed: $e');
  }
}

class StitchWorkerApp extends StatefulWidget {
  final NotificationService notificationService;
  final OfflineSyncService offlineSyncService;

  const StitchWorkerApp({
    super.key,
    required this.notificationService,
    required this.offlineSyncService,
  });

  @override
  State<StitchWorkerApp> createState() => _StitchWorkerAppState();
}

class _StitchWorkerAppState extends State<StitchWorkerApp> {
  late final PinService _pinService;
  late final LockStateProvider _lockState;
  late final IdleLockService _idleLock;
  late final PhoneOtpAuthProvider _phoneAuth;

  @override
  void initState() {
    super.initState();
    _pinService = PinService();
    _lockState = LockStateProvider(pinService: _pinService);
    _phoneAuth = PhoneOtpAuthProvider(
      backend: AuthBackend(
        baseUrl: RelayConfig.relayUrl.isNotEmpty ? RelayConfig.relayUrl : 'https://fcm-relay.example',
        secret: RelayConfig.relaySecret,
      ),
      firebaseAuth: AuthBackendFirebase(),
      pinService: _pinService,
    );
    _idleLock = IdleLockService(lockState: _lockState);
    _lockState.initialize();
    _idleLock.attach();
  }

  @override
  void dispose() {
    _idleLock.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: widget.notificationService),
        ChangeNotifierProvider<PhoneOtpAuthProvider>.value(value: _phoneAuth),
        ChangeNotifierProvider<LockStateProvider>.value(value: _lockState),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => WorkerProvider()),
        ChangeNotifierProxyProvider<WorkerProvider, TransactionProvider>(
          create: (_) => TransactionProvider(),
          update: (_, workerProvider, txProvider) {
            txProvider!.onTransactionApplied = (tx, direction) => workerProvider.applyTransactionDelta(tx, direction);
            return txProvider;
          },
        ),
        ChangeNotifierProvider(create: (_) => IncomeProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => DensityProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AuditProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => DebtProvider(debtService: DebtService(), notificationService: NotificationTriggerService())),
      ],
      child: Consumer3<ThemeProvider, SettingsProvider, DensityProvider>(
        builder: (context, themeProvider, settingsProvider, densityProvider, _) {
          return MaterialApp(
            title: 'Cofiz',
            locale: settingsProvider.locale,
            theme: AppTheme.lightTheme.copyWith(visualDensity: densityProvider.visualDensity),
            darkTheme: AppTheme.darkTheme.copyWith(visualDensity: densityProvider.visualDensity),
            themeMode: themeProvider.themeMode,
            debugShowCheckedModeBanner: false,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('am')],
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              final systemScale = mq.textScaler.scale(14) / 14;
              // Idle detection: Listener catches pointer, NotificationListener catches scroll
              return ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: AppToastHost(
                  child: MediaQuery(
                    data: mq.copyWith(textScaler: TextScaler.linear(systemScale * densityProvider.textScaleFactor)),
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (_) => _idleLock.onUserInteraction(),
                      onPointerMove: (_) => _idleLock.onUserInteraction(),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          _idleLock.onUserInteraction();
                          return false;
                        },
                        child: TelegramLoginListener(child: child!),
                      ),
                    ),
                  ),
                ),
              );
            },
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

/// Auth gate to check if user is logged in
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const Duration _minSplashDuration = Duration(milliseconds: 1400);

  bool _splashElapsed = false;

  @override
  void initState() {
    super.initState();
    // Ensure the branded splash animation plays fully even when the auth
    // check resolves instantly.
    Timer(_minSplashDuration, () {
      if (mounted) setState(() => _splashElapsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, LockStateProvider>(
      builder: (context, authProvider, lockState, _) {
        // Re-initialize lock state when uid changes (per-user PIN).
        if (authProvider.isAuthenticated && authProvider.user != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Provider.of<NotificationProvider>(context, listen: false).init(authProvider.user!.uid);
            lockState.initialize(uid: authProvider.user!.uid);
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Provider.of<NotificationProvider>(context, listen: false).disposeListener();
          });
        }
        if (authProvider.status == AuthStatus.uninitialized || !_splashElapsed) {
          return const AnimatedSplashScreen();
        }

        // PIN lock gates — forced after auth.
        if (authProvider.isAuthenticated) {
          if (lockState.state == PinLockState.awaitingFirstSetup) {
            return const CreatePinScreen();
          }
          if (lockState.state == PinLockState.locked) {
            return const PinLockScreen();
          }
        }

        // Navigate based on auth status AND user role
        if (authProvider.isAuthenticated) {
          if (authProvider.userRole == null) {
            if (authProvider.status == AuthStatus.loading) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
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

          switch (authProvider.userRole!) {
            case UserRole.admin:
              return MainLayout(
                  key: ValueKey('main-${authProvider.user!.uid}'));
            case UserRole.viewer:
              return MainLayout(
                  key: ValueKey('main-${authProvider.user!.uid}'));
            case UserRole.worker:
              if (authProvider.workerId != null) {
                return WorkerDashboardScreen(
                  key: ValueKey('worker-${authProvider.workerId}'),
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
    if (shouldAnimateTabSwitch(_currentIndex, index)) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _pageController.jumpToPage(index);
    }
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
