// In-app notification — mirrors a row from /api/notifications.
//
// Backend `type` values the app understands (see
// docs/laravel-notifications-extend-types.md for the source of truth):
//   - application              → new leave request (audience: approver/admins)
//   - approval                 → leave approved (audience: the employee)
//   - rejection                → leave rejected (audience: the employee)
//   - regularization_submitted → new attendance regularization request (audience: admins)
//   - onboarding_submitted     → new employee onboarding submitted (audience: admins)
//
// Unknown types render with a generic icon and fall through to the detail
// dialog on tap (rather than crashing or no-op'ing).

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../core/theme/app_colors.dart';

class NotificationItem {
  final int id;
  final int? leaveApplicationId;
  // Optional foreign keys for the non-leave notification types. The backend
  // may or may not populate these (per docs/laravel-notifications-extend-types.md
  // the columns are planned but optional). When present, the mobile app uses
  // them to drop the specific in-app notification once its action completes.
  final int? regularizationId;
  final int? onboardingId;
  final int userId;
  final String type;
  final String message;
  final bool isRead;
  final bool emailSent;
  final DateTime createdAt;
  final Map<String, dynamic>? leaveApplication;

  NotificationItem({
    required this.id,
    required this.userId,
    required this.type,
    required this.message,
    required this.isRead,
    required this.emailSent,
    required this.createdAt,
    this.leaveApplicationId,
    this.regularizationId,
    this.onboardingId,
    this.leaveApplication,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: _asInt(json['id']) ?? 0,
      leaveApplicationId: _asInt(json['leave_application_id']),
      regularizationId: _asInt(json['regularization_id']),
      onboardingId: _asInt(json['onboarding_id']),
      userId: _asInt(json['user_id']) ?? 0,
      type: (json['type'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      // API ships is_read / email_sent as 0/1 ints or sometimes bools — accept both.
      isRead: _asBool(json['is_read']),
      emailSent: _asBool(json['email_sent']),
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      leaveApplication: json['leave_application'] is Map<String, dynamic>
          ? json['leave_application'] as Map<String, dynamic>
          : null,
    );
  }

  NotificationItem copyWith({bool? isRead}) => NotificationItem(
        id: id,
        leaveApplicationId: leaveApplicationId,
        regularizationId: regularizationId,
        onboardingId: onboardingId,
        userId: userId,
        type: type,
        message: message,
        isRead: isRead ?? this.isRead,
        emailSent: emailSent,
        createdAt: createdAt,
        leaveApplication: leaveApplication,
      );

  // ---- Display getters used by the list tile ------------------------------

  /// What the icon and color should be for this notification's tile.
  IconData get icon {
    switch (type) {
      case 'application':
        return Iconsax.calendar_add;
      case 'approval':
        return Iconsax.tick_circle;
      case 'rejection':
        return Iconsax.close_circle;
      case 'regularization_submitted':
        return Iconsax.clock;
      case 'onboarding_submitted':
        return Iconsax.user_add;
      default:
        return Iconsax.notification;
    }
  }

  Color get color {
    switch (type) {
      case 'application':
        return AppColors.primary;
      case 'approval':
        return Colors.green;
      case 'rejection':
        return Colors.red;
      case 'regularization_submitted':
        return Colors.orange;
      case 'onboarding_submitted':
        return Colors.teal;
      default:
        return AppColors.primary;
    }
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${(diff.inDays / 7).floor()} weeks ago';
  }

  // ---- Helpers ------------------------------------------------------------

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static bool _asBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  static DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}

/// One page of notifications + the unread count the same response includes,
/// so the provider can update the bell badge without a separate API call.
class NotificationPage {
  final List<NotificationItem> items;
  final int currentPage;
  final int lastPage;
  final int total;
  final int unreadCount;

  NotificationPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.unreadCount,
  });

  bool get hasMore => currentPage < lastPage;

  factory NotificationPage.fromJson(Map<String, dynamic> root) {
    // Response shape:
    //   { success, message, data: {current_page, data:[], last_page, total, ...}, unread_count }
    final data = root['data'] as Map<String, dynamic>? ?? const {};
    final rawList = data['data'] as List<dynamic>? ?? const [];
    return NotificationPage(
      items: rawList
          .whereType<Map<String, dynamic>>()
          .map(NotificationItem.fromJson)
          .toList(),
      currentPage: NotificationItem._asInt(data['current_page']) ?? 1,
      lastPage: NotificationItem._asInt(data['last_page']) ?? 1,
      total: NotificationItem._asInt(data['total']) ?? 0,
      unreadCount: NotificationItem._asInt(root['unread_count']) ?? 0,
    );
  }
}
