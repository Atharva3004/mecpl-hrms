import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/notification_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../attendance/regularization_approval_screen.dart';
import '../leave/leave_approval_screen.dart';
import '../leave/leave_history_screen.dart';
import '../onboarding/employee_onboarding_approval_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Pull the first page once after the frame so we have a BuildContext that
    // can read the auth + notification providers. Prune expired items first so
    // the cached list from a previous visit doesn't show stale (>2 day old)
    // notifications while the network refresh is in flight.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().pruneExpired();
      _refresh();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Trigger a load-more when within 200px of the end of the list.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      final auth = context.read<AuthProvider>();
      final notif = context.read<NotificationProvider>();
      if (auth.token != null && notif.hasMore && !notif.isLoadingMore) {
        notif.loadMore(authToken: auth.token!);
      }
    }
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    await context.read<NotificationProvider>().refresh(authToken: auth.token!);
  }

  Future<void> _markAllRead() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    await context.read<NotificationProvider>().markAllAsRead(
          authToken: auth.token!,
        );
  }

  /// Tap on a notification item: mark it read (optimistic), then route to
  /// the right screen based on `type`.
  Future<void> _handleTap(NotificationItem item) async {
    final auth = context.read<AuthProvider>();
    if (auth.token != null && !item.isRead) {
      // Fire-and-forget — UI updates optimistically inside the provider.
      context.read<NotificationProvider>().markAsRead(
            authToken: auth.token!,
            id: item.id,
          );
    }

    if (!mounted) return;
    Widget? target;
    switch (item.type) {
      case 'application':
        // New leave request — surfaced to an approver/admin.
        target = const LeaveApprovalScreen();
        break;
      case 'approval':
      case 'rejection':
        // Outcome on the employee's own leave.
        target = const LeaveHistoryScreen();
        break;
      case 'regularization_submitted':
        // Admin broadcast — opens the pending regularizations list.
        target = const RegularizationApprovalScreen();
        break;
      case 'onboarding_submitted':
        // Admin broadcast — opens the pending onboardings list.
        target = const EmployeeOnboardingApprovalScreen();
        break;
    }
    if (target != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => target!));
    } else {
      _showDetail(item);
    }
  }

  void _showDetail(NotificationItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: item.color.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(item.icon, color: item.color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.timeAgo,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: isDark ? Colors.white54 : Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat(
                              'MMM dd, yyyy · hh:mm a',
                            ).format(item.createdAt),
                            style: AppTextStyles.labelSmall.copyWith(
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: isDark ? Colors.white12 : Colors.black12),
                const SizedBox(height: 16),
                Text(
                  item.message,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Close',
                      style: AppTextStyles.buttonText.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => Navigator.pop(context),
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
        title: Text(
          'Notifications',
          style: AppTextStyles.headlineSmall.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Consumer<NotificationProvider>(
            builder: (_, notif, __) {
              if (notif.unreadCount == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: _markAllRead,
                child: Text(
                  'Mark all read',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, notif, _) {
          if (notif.isLoading && notif.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (notif.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: _buildEmptyState(isDark),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: notif.items.length + (notif.hasMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index >= notif.items.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _buildNotificationItem(notif.items[index], index, isDark);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Iconsax.notification_status,
            size: 80,
            color: (isDark ? Colors.white : AppColors.textPrimary)
                .withOpacity(0.1),
          ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 24),
          Text('All caught up!', style: AppTextStyles.titleLarge),
          const SizedBox(height: 8),
          Text(
            'No new notifications at the moment.',
            style: AppTextStyles.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(
    NotificationItem item,
    int index,
    bool isDark,
  ) {
    // Unread tiles get a subtle accent strip + slightly stronger surface so
    // the user can scan the list at a glance.
    final unread = !item.isRead;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: unread
            ? Border(
                left: BorderSide(color: item.color, width: 4),
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _handleTap(item),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(item.icon, color: item.color, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.message,
                              style: AppTextStyles.titleSmall.copyWith(
                                fontWeight:
                                    unread ? FontWeight.bold : FontWeight.w500,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 8, top: 6),
                              decoration: BoxDecoration(
                                color: item.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.timeAgo,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: isDark ? Colors.white54 : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate(delay: (index * 30).ms).fadeIn(duration: 250.ms).slideY(
          begin: 0.05,
          end: 0,
          duration: 250.ms,
        );
  }
}
