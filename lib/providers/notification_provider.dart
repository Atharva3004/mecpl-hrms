// Server-driven notification list — backed by /api/notifications.
//
// Replaces the dashboard-activities-as-notifications shortcut. The bell badge
// reads `unreadCount` here; NotificationScreen reads `items` here. Pull-to-
// refresh hits `refresh()`; tapping an item calls `markAsRead(id)`; the
// "mark all" button calls `markAllAsRead()`.
import 'package:flutter/foundation.dart';

import '../models/notification_item.dart';
import '../services/api_service.dart';

class NotificationProvider extends ChangeNotifier {
  // How long a notification stays in the in-app list. Anything older than this
  // is pruned on every load/refresh so the screen only shows the last couple of
  // days' activity (today + yesterday) — older items "expire" and drop off
  // automatically after 2 days.
  static const Duration _retention = Duration(days: 2);

  final List<NotificationItem> _items = [];
  int _unreadCount = 0;
  int _currentPage = 0;
  int _lastPage = 1;
  int _total = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;

  List<NotificationItem> get items => List.unmodifiable(_items);
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _currentPage < _lastPage;
  int get total => _total;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => _items.isEmpty;

  /// True while the notification is still within the retention window and so
  /// should remain visible. Older items are treated as expired.
  bool _isRecent(NotificationItem n) =>
      DateTime.now().difference(n.createdAt) < _retention;

  /// Drops any expired (older-than-retention) items currently in the list and
  /// recomputes `unreadCount` from what's left, so the badge and the visible
  /// list never disagree. Returns true if anything was removed.
  bool _pruneExpired() {
    final before = _items.length;
    _items.removeWhere((n) => !_isRecent(n));
    if (_items.length == before) return false;
    _unreadCount = _items.where((n) => !n.isRead).length;
    _total = _items.length;
    return true;
  }

  /// Re-runs expiry against the current list (e.g. when the screen regains
  /// focus or the app resumes) and notifies listeners if anything dropped off.
  void pruneExpired() {
    if (_pruneExpired()) notifyListeners();
  }

  /// First load / pull-to-refresh. Replaces the list and resets pagination.
  Future<void> refresh({required String authToken}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final page = await ApiService.fetchNotifications(
        authToken: authToken,
        page: 1,
      );
      final recent = page.items.where(_isRecent).toList();
      _items
        ..clear()
        ..addAll(recent);
      _currentPage = page.currentPage;
      // Notifications come newest-first, so the moment a page contains an
      // expired item we've passed the 2-day cutoff — nothing recent remains on
      // later pages, so stop paginating to avoid a never-resolving spinner.
      _lastPage =
          recent.length < page.items.length ? page.currentPage : page.lastPage;
      // Counts reflect only the notifications we actually keep — expired items
      // shouldn't linger in the badge after they've dropped off the list.
      _total = _items.length;
      _unreadCount = _items.where((n) => !n.isRead).length;
    } catch (e) {
      _errorMessage = e.toString();
      if (kDebugMode) debugPrint('NotificationProvider.refresh failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Loads the next page when the user scrolls near the bottom. No-op if
  /// there's nothing more to load or another load is already in flight.
  Future<void> loadMore({required String authToken}) async {
    if (_isLoadingMore || !hasMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final page = await ApiService.fetchNotifications(
        authToken: authToken,
        page: _currentPage + 1,
      );
      final recent = page.items.where(_isRecent).toList();
      _items.addAll(recent);
      _currentPage = page.currentPage;
      _lastPage =
          recent.length < page.items.length ? page.currentPage : page.lastPage;
      _total = _items.length;
      _unreadCount = _items.where((n) => !n.isRead).length;
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationProvider.loadMore failed: $e');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Lightweight badge refresh — used on app resume / when a push arrives.
  /// Doesn't touch the list, just updates `unreadCount`.
  Future<void> refreshUnreadCount({required String authToken}) async {
    try {
      final count = await ApiService.fetchUnreadCount(authToken: authToken);
      if (count != _unreadCount) {
        _unreadCount = count;
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('refreshUnreadCount failed: $e');
    }
  }

  /// Marks one notification read. Optimistic: flips the local flag and
  /// decrements `unreadCount` immediately, then confirms with the backend.
  /// Reverts on failure so the badge doesn't drift from server truth.
  Future<void> markAsRead({
    required String authToken,
    required int id,
  }) async {
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx == -1) return;
    final wasUnread = !_items[idx].isRead;
    if (!wasUnread) return; // already read — nothing to do

    // Optimistic update
    _items[idx] = _items[idx].copyWith(isRead: true);
    if (_unreadCount > 0) _unreadCount -= 1;
    notifyListeners();

    final ok = await ApiService.markNotificationRead(
      authToken: authToken,
      notificationId: id,
    );
    if (!ok) {
      // Revert
      _items[idx] = _items[idx].copyWith(isRead: false);
      _unreadCount += 1;
      notifyListeners();
    }
  }

  /// Marks every notification in the current list as read. Optimistic again
  /// — flips all local flags and zeros the badge, reverts if the API call
  /// fails (rare, since the endpoint is idempotent).
  Future<void> markAllAsRead({required String authToken}) async {
    if (_unreadCount == 0) return;
    final previous = [..._items];
    final previousCount = _unreadCount;

    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].isRead) {
        _items[i] = _items[i].copyWith(isRead: true);
      }
    }
    _unreadCount = 0;
    notifyListeners();

    final ok = await ApiService.markAllNotificationsRead(authToken: authToken);
    if (!ok) {
      _items
        ..clear()
        ..addAll(previous);
      _unreadCount = previousCount;
      notifyListeners();
    }
  }

  /// Local-only removal of items matching [test]. Decrements `unreadCount`
  /// by however many of the removed items were still unread, and notifies
  /// listeners if anything actually changed.
  ///
  /// Used by the approval flows so that once an admin/manager actions a
  /// request, the in-app notification that prompted the action disappears
  /// from the list without waiting for a backend re-fetch.
  void removeWhere(bool Function(NotificationItem) test) {
    final removedUnread = _items.where((n) => test(n) && !n.isRead).length;
    final before = _items.length;
    _items.removeWhere(test);
    if (_items.length == before) return;
    if (removedUnread > 0) {
      _unreadCount = (_unreadCount - removedUnread).clamp(0, _unreadCount);
    }
    _total = (_total - (before - _items.length)).clamp(0, _total);
    notifyListeners();
  }

  /// Removes the in-app notification for a specific leave application —
  /// typically the `application` type notification surfaced to approvers
  /// once the underlying leave has been approved or rejected.
  void removeForLeaveApplication(int leaveApplicationId) {
    removeWhere((n) => n.leaveApplicationId == leaveApplicationId);
  }

  /// Removes the in-app notification tied to a specific regularization
  /// request. Relies on the backend populating `regularization_id` on the
  /// notification row (planned per docs/laravel-notifications-extend-types.md).
  /// If the backend hasn't shipped that yet, this is a no-op and callers
  /// should fall back to a heuristic (e.g. employee-name match on the
  /// notification message).
  void removeForRegularization(int regularizationId) {
    removeWhere((n) => n.regularizationId == regularizationId);
  }

  /// Removes the in-app notification tied to a specific onboarding record.
  /// Same backend-support story as `removeForRegularization` — no-op until
  /// the `onboarding_id` column is populated on the notification row.
  void removeForOnboarding(int onboardingId) {
    removeWhere((n) => n.onboardingId == onboardingId);
  }

  /// Wipes all state. Called on logout so a new user doesn't see the
  /// previous user's list flash before the next refresh.
  void clear() {
    _items.clear();
    _unreadCount = 0;
    _currentPage = 0;
    _lastPage = 1;
    _total = 0;
    _errorMessage = null;
    notifyListeners();
  }
}
