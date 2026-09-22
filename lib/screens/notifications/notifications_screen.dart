import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _selectedCategory = 'All';

  final List<Map<String, dynamic>> _allNotifications = [
    {
      'id': '1',
      'title': 'Leave Request Approved',
      'message':
          'Your leave request for Dec 15-17 has been approved by your manager.',
      'time': '5 min ago',
      'type': 'Leave',
      'isRead': false,
      'icon': Iconsax.tick_circle,
      'color': AppColors.success,
    },
    {
      'id': '2',
      'title': 'Payslip Generated',
      'message': 'Your November 2024 payslip is now available for download.',
      'time': '2 hours ago',
      'type': 'Payroll',
      'isRead': false,
      'icon': Iconsax.receipt,
      'color': AppColors.primary,
    },
    {
      'id': '3',
      'title': 'Clock-in Reminder',
      'message': 'Don\'t forget to clock in for today. It\'s 9:15 AM.',
      'time': '3 hours ago',
      'type': 'Attendance',
      'isRead': true,
      'icon': Iconsax.clock,
      'color': AppColors.warning,
    },
    {
      'id': '4',
      'title': 'Team Meeting',
      'message': 'Weekly team meeting scheduled for today at 3:00 PM.',
      'time': 'Yesterday',
      'type': 'General',
      'isRead': true,
      'icon': Iconsax.calendar,
      'color': AppColors.info,
    },
    {
      'id': '5',
      'title': 'Performance Review',
      'message':
          'Your quarterly performance review is due. Please complete self-assessment.',
      'time': 'Yesterday',
      'type': 'General',
      'isRead': true,
      'icon': Iconsax.chart,
      'color': AppColors.secondary,
    },
    {
      'id': '6',
      'title': 'Holiday Announcement',
      'message': 'Office will be closed on Dec 25 for Christmas holiday.',
      'time': '2 days ago',
      'type': 'General',
      'isRead': true,
      'icon': Iconsax.gift,
      'color': AppColors.error,
    },
  ];

  List<Map<String, dynamic>> get _filteredNotifications {
    if (_selectedCategory == 'All') return _allNotifications;
    return _allNotifications
        .where((n) => n['type'] == _selectedCategory)
        .toList();
  }

  void _markAsRead(String id) {
    setState(() {
      final index = _allNotifications.indexWhere((n) => n['id'] == id);
      if (index != -1) {
        _allNotifications[index]['isRead'] = true;
      }
    });
  }

  void _markAllAsRead() {
    setState(() {
      for (var n in _allNotifications) {
        n['isRead'] = true;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All notifications marked as read'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _deleteNotification(String id) {
    setState(() {
      _allNotifications.removeWhere((n) => n['id'] == id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(context, isDark),
          SliverToBoxAdapter(child: _buildCategoryFilters(isDark)),
          _buildNotificationList(isDark),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, bool isDark) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      surfaceTintColor: Colors.transparent,
      title: Text(
        'Notifications',
        style: AppTextStyles.headlineLarge.copyWith(
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
      ),
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Icon(
          Icons.chevron_left,
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
      ),
      actions: [
        IconButton(
          onPressed: _markAllAsRead,
          icon: const Icon(Iconsax.tick_circle, color: AppColors.primary),
          tooltip: 'Mark all as read',
        ),
      ],
    );
  }

  Widget _buildCategoryFilters(bool isDark) {
    final categories = ['All', 'Attendance', 'Payroll', 'Leave', 'General'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: categories.map((cat) {
            final isSelected = _selectedCategory == cat;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilterChip(
                selected: isSelected,
                label: Text(cat),
                onSelected: (selected) {
                  setState(() => _selectedCategory = cat);
                },
                backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : AppColors.textSecondary),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected
                        ? Colors.transparent
                        : (isDark ? AppColors.darkBorder : AppColors.border),
                  ),
                ),
                showCheckmark: false,
                elevation: isSelected ? 4 : 0,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildNotificationList(bool isDark) {
    final notifications = _filteredNotifications;

    if (notifications.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Iconsax.notification_bing,
                size: 80,
                color: isDark ? Colors.white12 : Colors.grey[300],
              ),
              const SizedBox(height: 16),
              Text(
                'No notifications found',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final notification = notifications[index];
          return _buildNotificationItem(notification, index, isDark);
        }, childCount: notifications.length),
      ),
    );
  }

  Widget _buildNotificationItem(
    Map<String, dynamic> notification,
    int index,
    bool isDark,
  ) {
    final isRead = notification['isRead'] as bool;
    final color = notification['color'] as Color;

    return Dismissible(
      key: Key(notification['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.8),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(Iconsax.trash, color: Colors.white),
      ),
      onDismissed: (_) => _deleteNotification(notification['id']),
      child: GestureDetector(
        onTap: () => _markAsRead(notification['id']),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isRead
                  ? Colors.transparent
                  : AppColors.primary.withOpacity(0.2),
              width: 1,
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  notification['icon'] as IconData,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          notification['type'] as String,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          notification['time'] as String,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification['title'] as String,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification['message'] as String,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDark
                            ? Colors.white70
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isRead)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 20),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ).animate(delay: (index * 50).ms).fadeIn().slideY(begin: 0.1, end: 0),
    );
  }
}
