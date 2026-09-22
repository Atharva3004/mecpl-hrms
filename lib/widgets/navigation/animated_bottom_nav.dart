// Animated Bottom Navigation Bar - Glassmorphism Style
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

class AnimatedBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<NavItem> items;

  const AnimatedBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurface.withOpacity(0.9)
            : AppColors.white.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [],
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height:
                AppConstants.bottomNavHeight +
                MediaQuery.of(context).padding.bottom,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder.withOpacity(0.3)
                      : AppColors.border.withOpacity(0.5),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                items.length,
                (index) => _NavItemWidget(
                  item: items[index],
                  isSelected: currentIndex == index,
                  onTap: () => onTap(index),
                  index: index,
                ),
              ),
            ),
          ),
        ),
      ),
    ); // .animate().fadeIn(duration: 400.ms).slideY(begin: 0.3, end: 0);
  }
}

class _NavItemWidget extends StatelessWidget {
  final NavItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final int index;

  const _NavItemWidget({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? AppColors.primary
        : Theme.of(context).colorScheme.onSurface.withOpacity(0.4);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? item.activeIcon : item.icon,
              size: AppConstants.bottomNavIconSize,
              color: color,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

// Default navigation items for different roles
class NavItems {
  static List<NavItem> getItemsForRole(bool canViewReports) {
    return [
      const NavItem(
        label: 'Dashboard',
        icon: Iconsax.home_2,
        activeIcon: Iconsax.home_2,
      ),
      const NavItem(
        label: 'Attendance',
        icon: Iconsax.calendar_2,
        activeIcon: Iconsax.calendar_2,
      ),
      // const NavItem(
      //   label: 'Payroll',
      //   icon: Iconsax.wallet_2,
      //   activeIcon: Iconsax.wallet_2,
      // ),
      const NavItem(
        label: 'Leave',
        icon: Iconsax.airplane,
        activeIcon: Iconsax.airplane,
      ),
      const NavItem(
        label: 'Profile',
        icon: Iconsax.user,
        activeIcon: Iconsax.user,
      ),
    ];
  }

  static List<NavItem> get defaultItems => [
    const NavItem(
      label: 'Dashboard',
      icon: Iconsax.home_2,
      activeIcon: Iconsax.home_2,
    ),
    const NavItem(
      label: 'Attendance',
      icon: Iconsax.calendar_2,
      activeIcon: Iconsax.calendar_2,
    ),
    // const NavItem(
    //   label: 'Payroll',
    //   icon: Iconsax.wallet_2,
    //   activeIcon: Iconsax.wallet_2,
    // ),
    const NavItem(
      label: 'Leave',
      icon: Iconsax.calendar_tick,
      activeIcon: Iconsax.calendar_tick,
    ),
    const NavItem(
      label: 'Profile',
      icon: Iconsax.user,
      activeIcon: Iconsax.user,
    ),
  ];
}
