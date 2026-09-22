// FCM + local-notification plumbing. Three delivery paths to handle:
//   1. App in foreground — onMessage fires, FCM does NOT pop a panel
//      notification, so we render one ourselves via flutter_local_notifications.
//   2. App backgrounded — FCM auto-renders the panel notification using the
//      default channel + icon declared in AndroidManifest.xml.
//   3. App killed — same as backgrounded; the OS wakes us when the user taps.
//
// Three TAP entry points (each fires in a different lifecycle state):
//   a. Cold start (app was killed when the notification arrived) →
//      `getInitialMessage()` once, after init.
//   b. Background → tap brings app forward → `onMessageOpenedApp` fires.
//   c. Foreground → user taps the heads-up we rendered ourselves →
//      `onDidReceiveNotificationResponse` fires from flutter_local_notifications.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show navigatorKey;
import '../providers/navigation_provider.dart';
import '../screens/attendance/regularization_approval_screen.dart';
import '../screens/leave/leave_approval_screen.dart';
import '../screens/leave/leave_history_screen.dart';
import '../screens/notifications/notification_screen.dart';
import '../screens/onboarding/employee_onboarding_approval_screen.dart';
import 'api_service.dart';

/// Mirrors the SharedPreferences key in `auth_provider.dart`. Kept as a
/// const here so the token-refresh path can read the auth token without
/// importing AuthProvider (which would create a circular dependency).
const String _kAuthTokenPref = 'auth_token';

/// Stores a notification route the user tapped while the authenticated shell
/// (`MainShell`) wasn't on screen — typically because the user was logged out
/// or the app was still bootstrapping. `MainShell.initState` consumes this on
/// mount, so the deep-link survives the login flow and even cold starts.
const String _kPendingRoutePref = 'pending_notification_route';

/// Channel id mirrored in AndroidManifest.xml's
/// `default_notification_channel_id` meta-data. Changing one without the other
/// will break panel notifications when the app is killed.
const String _channelId = 'mecpl_default';
const String _channelName = 'MECPL HRMS';
const String _channelDesc = 'General app notifications';

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Runs in a separate isolate (the main app may be terminated). Two modes:
  //
  //   (a) Backend sends a `notification` payload — FCM auto-renders the
  //       panel notification with the channel's default small icon. We do
  //       NOTHING here; rendering ourselves would create duplicates.
  //
  //   (b) Backend sends a data-only payload — FCM does not render anything,
  //       so we render the local notification ourselves with both small AND
  //       large icons. This is the only way to get the MECPL logo on the
  //       right side of background/killed notifications (FCM v1 has no
  //       large-icon field). See docs/laravel-fcm-data-only-payloads.md.
  await Firebase.initializeApp();

  if (message.notification != null) return; // mode (a) — FCM handled it

  // mode (b) — render ourselves.
  final local = FlutterLocalNotificationsPlugin();
  await local.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
      iOS: DarwinInitializationSettings(),
    ),
  );

  final data = message.data;
  final title = data['title']?.toString() ?? 'MECPL HRMS';
  final body = data['body']?.toString() ?? '';

  // Strip title/body from the data payload before encoding the tap payload so
  // we don't try to route to `title` etc.
  final routeData = Map<String, dynamic>.from(data)
    ..remove('title')
    ..remove('body');

  await local.show(
    message.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/launcher_icon',
        largeIcon: const DrawableResourceAndroidBitmap('notification_logo'),
      ),
      iOS: const DarwinNotificationDetails(),
    ),
    payload: routeData.isEmpty
        ? null
        : routeData.entries.map((e) => '${e.key}=${e.value}').join(';'),
  );
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static String? _cachedToken;

  /// True once `MainShell` has mounted (i.e. the user is past login + biometric
  /// + bootstrap and is looking at the authenticated UI). Tap-routing is only
  /// safe to execute in this state — otherwise we persist the route and let
  /// `MainShell.initState` drain it on mount.
  static bool _shellReady = false;

  /// Returns the FCM device token once registered. Backend stores this
  /// alongside the user so it can target this specific device.
  static String? get token => _cachedToken;

  /// Called by `MainShell.initState` once the authenticated shell is on
  /// screen. Drains any pending notification route (e.g. one tapped while
  /// the user was on the login screen).
  static Future<void> markShellReady() async {
    _shellReady = true;
    await _consumePendingRoute();
  }

  /// Called by `MainShell.dispose` when the user logs out. Subsequent taps
  /// will be persisted instead of executed until the shell mounts again.
  static void markShellGone() {
    _shellReady = false;
  }

  static Future<void> init() async {
    await Firebase.initializeApp();

    // Ask the user (Android 13+, iOS) — silently no-ops on older Androids.
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Local notifications — used for the foreground path only.
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      // Foreground tap (path c). Payload was passed in via `_local.show(...)`
      // below as a flat string — we re-route through the same handler.
      onDidReceiveNotificationResponse: (response) {
        _handleRoute(_decodePayload(response.payload));
      },
    );

    // Pre-create the channel so the first foreground notification doesn't
    // arrive with default importance.
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
          ),
        );

    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // Path 1: app foreground — render local notification with the data
    // payload encoded so a tap can route correctly.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification == null) return;
      _local.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            // Small icon (top-left of the notification + status bar). Must be
            // monochrome on Android 8+; we use the launcher_icon and rely on
            // Android to auto-mask it. Set via meta-data in AndroidManifest too.
            icon: '@mipmap/launcher_icon',
            // Large icon (right-hand side of the notification body). Uses the
            // splash drawable which is the centred MECPL logo. NOTE: this
            // affects FOREGROUND notifications only — FCM auto-renders
            // background/killed notifications without a large-icon field.
            // See docs/laravel-fcm-data-only-payloads.md for the backend
            // change needed to get the logo on background notifications too.
            largeIcon: const DrawableResourceAndroidBitmap('notification_logo'),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: _encodePayload(message.data),
      );
    });

    // Path b: app was backgrounded, user tapped the panel notification.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleRoute(message.data);
    });

    // Path a: app was killed, user tapped the panel notification → app cold-
    // starts. Has to be checked once after init; isn't a stream.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // Defer until after the first frame so the navigator and providers exist.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleRoute(initial.data);
      });
    }

    _cachedToken = await FirebaseMessaging.instance.getToken();
    if (kDebugMode) {
      debugPrint('FCM token: $_cachedToken');
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      _cachedToken = newToken;
      // If a user is currently logged in, push the new token up to the
      // backend so it can keep targeting this device. If not logged in
      // (fresh install / post-logout), the next login will send the token
      // via the normal login payload — nothing to do here.
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString(_kAuthTokenPref);
      if (authToken == null || authToken.isEmpty) return;
      await ApiService.updateFcmToken(
        authToken: authToken,
        fcmToken: newToken,
      );
    });
  }

  // ---- Routing ------------------------------------------------------------

  /// Routing entry point — called from every tap path (cold start,
  /// background, foreground). If the authenticated shell is on screen, the
  /// route fires immediately; otherwise it's persisted for `MainShell` to
  /// pick up after the user logs in / biometric-unlocks / finishes bootstrap.
  ///
  /// Payload examples sent from backend (FCM `data` field):
  ///   {"route": "notifications"}                 → opens NotificationScreen
  ///   {"route": "leave_approvals"}               → opens LeaveApprovalScreen (manager view)
  ///   {"route": "leave_history"}                 → opens LeaveHistoryScreen (employee view)
  ///   {"route": "regularization_approvals"}      → opens RegularizationApprovalScreen
  ///   {"route": "onboarding_approvals"}          → opens EmployeeOnboardingApprovalScreen
  ///   {"route": "tab", "tab": "leave"}           → switches bottom-nav to Leave
  ///   {"route": "tab", "tab": "attendance"}      → switches bottom-nav to Attendance
  static Future<void> _handleRoute(Map<String, dynamic> data) async {
    if (data.isEmpty || data['route'] == null) return;

    if (!_shellReady) {
      // User is on login screen / biometric lock / loading scaffold — stash
      // the route so MainShell.initState can route to it after login.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPendingRoutePref, _encodePayload(data));
      return;
    }
    _routeNow(data);
  }

  /// Reads + clears any persisted pending route and executes it on the next
  /// frame. Called from `markShellReady()` so the shell drains the route as
  /// soon as it's on screen.
  static Future<void> _consumePendingRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString(_kPendingRoutePref);
    if (pending == null || pending.isEmpty) return;
    await prefs.remove(_kPendingRoutePref);

    // MainShell is mounting this frame — defer one frame so its IndexedStack
    // and Navigator are fully built before we push / switch tabs on them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeNow(_decodePayload(pending));
    });
  }

  /// Actually performs the navigation. Only safe to call when MainShell is
  /// in the tree. All callers go through `_handleRoute` /
  /// `_consumePendingRoute`, which guard for that.
  static void _routeNow(Map<String, dynamic> data) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final route = data['route']?.toString();
    switch (route) {
      case 'notifications':
        Navigator.of(ctx).push(
          MaterialPageRoute(builder: (_) => const NotificationScreen()),
        );
        break;
      case 'leave_approvals':
        // Manager-side: opens the list of pending leave requests to approve.
        // Backend sends this when a new leave request is submitted that needs
        // *this user's* approval (recipient = the manager/HR).
        Navigator.of(ctx).push(
          MaterialPageRoute(builder: (_) => const LeaveApprovalScreen()),
        );
        break;
      case 'leave_history':
        // Employee-side: opens the user's own leave history list. Backend
        // sends this when *this user's* leave is approved/rejected.
        Navigator.of(ctx).push(
          MaterialPageRoute(builder: (_) => const LeaveHistoryScreen()),
        );
        break;
      case 'regularization_approvals':
        // Admin/approver side: opens the pending regularization requests
        // list. Backend sends this when an employee submits a new
        // attendance-regularization request.
        Navigator.of(ctx).push(
          MaterialPageRoute(builder: (_) => const RegularizationApprovalScreen()),
        );
        break;
      case 'onboarding_approvals':
        // Admin side: opens the pending onboarding approvals list. Backend
        // sends this when a new employee onboarding needs admin approval.
        Navigator.of(ctx).push(
          MaterialPageRoute(builder: (_) => const EmployeeOnboardingApprovalScreen()),
        );
        break;
      case 'tab':
        final tab = data['tab']?.toString();
        final index = _tabIndex(tab);
        if (index != null) {
          ctx.read<NavigationProvider>().setIndex(index);
        }
        break;
      default:
        // Unknown / no payload — leave the user wherever they were.
        break;
    }
  }

  /// Maps the named tab from a notification payload onto the bottom-nav index
  /// used by `MainShell`'s IndexedStack.
  static int? _tabIndex(String? tab) {
    switch (tab) {
      case 'dashboard':
        return 0;
      case 'attendance':
        return 1;
      case 'leave':
        return 2;
      case 'profile':
        return 3;
      default:
        return null;
    }
  }

  // FCM `data` is Map<String,String>; flutter_local_notifications carries a
  // single string payload. We round-trip via `key=value;key=value` so the
  // foreground tap path can recover the same routing info.
  static String _encodePayload(Map<String, dynamic> data) =>
      data.entries.map((e) => '${e.key}=${e.value}').join(';');

  static Map<String, dynamic> _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    return {
      for (final pair in payload.split(';'))
        if (pair.contains('='))
          pair.split('=').first: pair.substring(pair.indexOf('=') + 1),
    };
  }
}
