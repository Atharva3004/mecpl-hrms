// MECPL HRMS - Main Entry Point
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:workmanager/workmanager.dart';

// Core
import 'core/theme/app_theme.dart';

// Providers
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/attendance_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/holiday_provider.dart';
import 'providers/location_history_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/permission_provider.dart';

// Services
import 'services/api_service.dart';
import 'services/background_ping_worker.dart';
import 'services/notification_service.dart';
import 'services/session_manager.dart';

// Screens
import 'screens/auth/login_screen.dart';
import 'screens/auth/biometric_lock_screen.dart';
import 'screens/shell/main_shell.dart';
import 'widgets/common/custom_loader.dart';

/// Used by `SessionManager`'s 401 listener to surface a snackbar from outside
/// the widget tree (e.g. when a background API call detects an expired token
/// while the user is mid-navigation).
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Global navigator key — lets `NotificationService` push routes / switch
/// bottom-nav tabs when the user taps a system notification, even though that
/// callback fires outside of any BuildContext.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // FCM + local notifications. Fire-and-forget so cold start (especially the
  // notification-tap path with the app killed) doesn't wait on Firebase init
  // / token fetch / network round-trips before the first frame paints. The
  // FCM token may briefly be null on the very first login after install —
  // the onTokenRefresh listener back-fills via /update-fcm-token shortly
  // after, and pending notification routes survive via SharedPreferences.
  unawaited(NotificationService.init());

  // Initialize the background ping scheduler. Must run before any screen
  // calls `BackgroundLocationService().startTracking(...)`. The callback
  // dispatcher lives in `lib/services/background_ping_worker.dart` — it's
  // what the OS invokes when it wakes the app up to send a ping.
  Workmanager().initialize(backgroundPingCallbackDispatcher);

  // Required before the attendance foreground service can run its TaskHandler
  // isolate (flutter_foreground_task README, step 1). Without it the service
  // starts and shows its notification, but the handler's onStart /
  // onRepeatEvent never fire — the service is alive and doing nothing, which
  // is exactly how "notification present, no pings" looks.
  FlutterForegroundTask.initCommunicationPort();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => HolidayProvider()),
        ChangeNotifierProvider(create: (_) => LocationHistoryProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => PermissionProvider()),
      ],
      child: const MECPLApp(),
    ),
  );
}

class MECPLApp extends StatefulWidget {
  const MECPLApp({super.key});

  @override
  State<MECPLApp> createState() => _MECPLAppState();
}

class _MECPLAppState extends State<MECPLApp> {
  /// Guards against re-entrancy while a 401 is being verified — several API
  /// calls can 401 in quick succession; we only run one validate/logout cycle.
  bool _handlingExpiry = false;

  @override
  void initState() {
    super.initState();
    // Global 401 handler: any API call seeing a 401 fires SessionManager.
    // We DON'T trust that 401 blindly — a single endpoint can return 401 for
    // reasons other than a dead token (a flaky call, a background ping, a
    // server quirk). The backend confirmed tokens don't expire and are only
    // revoked on explicit logout, so before tearing the session down we
    // re-check the token via /validate-token and only log out if it's truly
    // gone. The tree swaps to LoginScreen because `auth.isAuthenticated` flips.
    SessionManager.instance.sessionExpired.addListener(_handleSessionExpired);
  }

  @override
  void dispose() {
    SessionManager.instance.sessionExpired.removeListener(
      _handleSessionExpired,
    );
    super.dispose();
  }

  Future<void> _handleSessionExpired() async {
    final expiry = SessionManager.instance.sessionExpired.value;
    if (expiry == null || !mounted) return;

    final auth = context.read<AuthProvider>();
    // Avoid a redundant logout flow if the user is already on the login
    // screen (e.g. two background calls 401 in quick succession).
    if (!auth.isAuthenticated && !auth.needsBiometricUnlock) return;
    if (_handlingExpiry) return;
    _handlingExpiry = true;

    try {
      // Confirm the token is actually dead before logging out. validateToken
      // returns false on a real 401 (without re-firing SessionManager) and
      // throws on network errors.
      final token = auth.token;
      if (token != null && token.isNotEmpty) {
        try {
          final stillValid = await ApiService.validateToken(token);
          if (stillValid) {
            // False alarm — the token is fine. Clear the signal and stay in.
            SessionManager.instance.reset();
            return;
          }
        } catch (_) {
          // Couldn't reach /validate-token (offline / transient). Don't punish
          // the user for a connectivity blip — keep the session; a later real
          // call will surface a genuine expiry if the token is actually dead.
          SessionManager.instance.reset();
          return;
        }
      }

      if (!mounted) return;
      final reason =
          expiry.reason ?? 'Your session has expired. Please login again.';
      auth.forceLogout(reason: reason);
      SessionManager.instance.reset();

      scaffoldMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(reason),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
    } finally {
      _handlingExpiry = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final authProvider = context.watch<AuthProvider>();

    return MaterialApp(
      title: 'MECPL HRMS',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      // Clamp the system font/display-size scale so aggressive device
      // defaults (Oppo/Vivo/Samsung ship large defaults, and users bump
      // them further) can't grow text enough to overflow or wrap our
      // fixed-layout cards. Applies app-wide, on top of every screen.
      // Only cap the upper end. A minScaleFactor of 1.0 here collides with
      // built-in Material widgets that clamp their own labels to
      // maxScaleFactor 1.0 (e.g. BottomNavigationBar): Flutter combines the
      // two into a _ClampedTextScaler(1.0, 1.0) and asserts maxScale > minScale,
      // crashing the screen. Leaving the floor at the default (0.0) avoids the
      // collision while still preventing large device defaults from overflowing.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: child!,
      ),
      home: _getHome(themeProvider, authProvider),
    );
  }

  Widget _getHome(ThemeProvider theme, AuthProvider auth) {
    // Hold on a loader until both theme and the auth bootstrap (reads token +
    // biometric flag from SharedPreferences) have settled. Prevents a flash
    // of the login screen before the biometric prompt.
    if (!theme.isLoaded || auth.isBootstrapping) {
      return const Scaffold(
        key: ValueKey('loading_scaffold'),
        body: Center(child: CustomLoader(size: 60)),
      );
    }

    if (auth.needsBiometricUnlock) {
      return const BiometricLockScreen(key: ValueKey('biometric_lock_screen'));
    }

    if (auth.isAuthenticated) {
      return const MainShell(key: ValueKey('main_shell'));
    }
    return const LoginScreen(key: ValueKey('login_screen'));
  }
}
