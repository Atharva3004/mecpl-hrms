// App Drawer - Attractive & Professional Navigation
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:mecpl_flutter/core/theme/app_colors.dart';
import 'package:mecpl_flutter/widgets/common/logo_loader.dart';
import 'package:mecpl_flutter/core/theme/app_text_styles.dart';
import 'package:mecpl_flutter/models/role_model.dart';
import 'package:mecpl_flutter/providers/auth_provider.dart';
import 'package:mecpl_flutter/screens/profile/profile_screen.dart';
import 'package:mecpl_flutter/screens/documents/my_documents_screen.dart';
import 'package:mecpl_flutter/screens/profile/achievements_screen.dart';
import 'package:mecpl_flutter/screens/profile/resignation_screen.dart';
import 'package:mecpl_flutter/screens/settings/settings_screen.dart';
import 'package:mecpl_flutter/screens/useful_links/useful_links_screen.dart';
import 'package:mecpl_flutter/screens/hr_policy/hr_policy_screen.dart';
// import 'package:mecpl_flutter/screens/admin/permission_management_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkBackground.withOpacity(0.95)
              : AppColors.background.withOpacity(0.95),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            children: [
              _buildHeader(context, isDark),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  child: Consumer<AuthProvider>(
                    builder: (context, auth, child) {
                      final role = auth.currentUser?.role ?? UserRole.employee;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle('Menu'),
                          const SizedBox(height: 12),
                          ..._buildMenuItems(context, role, isDark),
                        ],
                      );
                    },
                  ),
                ),
              ),
              _buildFooter(context, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateWithLoader(BuildContext context, Widget screen) async {
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: const Center(child: LogoLoader(width: 60, height: 60)),
      ),
    );

    // Initial wait
    await Future.delayed(const Duration(milliseconds: 1000));

    // Close loader
    navigator.pop();

    // Navigate
    navigator.push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final user = auth.currentUser;
        final name = user?.fullName ?? 'User';
        // Format: #EMP001 | Manager
        final empCode = user?.employeeId ?? '';
        final role = user?.role.displayName ?? 'Employee';
        final subtitle = empCode.isNotEmpty ? '#$empCode | $role' : role;

        final initial = name.isNotEmpty ? name[0] : 'U';

        return Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 20,
            bottom: 20,
            left: 20,
            right: 20,
          ),
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          child: Row(
            children: [
              // Avatar Circle
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.4),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: Colors.white,
                      fontSize: 24,
                    ),
                  ),
                ),
              ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),

              const SizedBox(width: 16),

              // Name and Role Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                          name,
                          style: AppTextStyles.titleLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                        .animate()
                        .fadeIn(delay: 200.ms)
                        .slideX(begin: 0.2, end: 0),

                    const SizedBox(height: 4),

                    Text(
                          subtitle,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                        .animate()
                        .fadeIn(delay: 300.ms)
                        .slideX(begin: 0.2, end: 0),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildMenuItems(
    BuildContext context,
    UserRole role,
    bool isDark,
  ) {
    return [
      _buildDrawerItem(
        context: context,
        icon: Iconsax.user_square,
        title: 'My Profile',
        color: AppColors.info,
        onTap: () => _navigateWithLoader(context, const ProfileScreen()),
        isDark: isDark,
      ),
      // Form 16 and the Medical Health Card live here rather than under
      // Useful Links — they're the employee's own documents, not external
      // portals.
      _buildDrawerItem(
        context: context,
        icon: Iconsax.folder_2,
        title: 'My Documents',
        color: AppColors.primary,
        onTap: () => _navigateWithLoader(context, const MyDocumentsScreen()),
        isDark: isDark,
      ),
      // Achievements & Career Transition are hidden for the Director role.
      if (role != UserRole.director) ...[
        _buildDrawerItem(
          context: context,
          icon: Iconsax.award,
          title: 'Achievements',
          color: AppColors.warning,
          onTap: () => _navigateWithLoader(context, const AchievementsScreen()),
          isDark: isDark,
        ),
        _buildDrawerItem(
          context: context,
          icon: Iconsax.logout,
          title: 'Carrer Transition',
          color: AppColors.error,
          onTap: () => _navigateWithLoader(context, const ResignationScreen()),
          isDark: isDark,
        ),
      ],
      _buildDrawerItem(
        context: context,
        icon: Iconsax.link,
        title: 'Useful Links',
        color: AppColors.success,
        onTap: () => _navigateWithLoader(context, const UsefulLinksScreen()),
        isDark: isDark,
      ),
      _buildDrawerItem(
        context: context,
        icon: Iconsax.book_1,
        title: 'HR Policy',
        color: AppColors.primary,
        onTap: () => _navigateWithLoader(context, const HrPolicyScreen()),
        isDark: isDark,
      ),
      _buildDrawerItem(
        context: context,
        icon: Iconsax.setting,
        title: 'Settings',
        color: AppColors.secondary,
        onTap: () => _navigateWithLoader(context, const SettingsScreen()),
        isDark: isDark,
      ),
      // if (role == UserRole.admin)
      //   _buildDrawerItem(
      //     context: context,
      //     icon: Iconsax.shield_tick,
      //     title: 'Permission Management',
      //     color: AppColors.primary,
      //     onTap: () =>
      //         // _navigateWithLoader(context, const PermissionManagementScreen()),
      //     isDark: isDark,
      //   ),
    ];
  }

  Widget _buildDrawerItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
    bool isSubItem = false,
  }) {
    return Container(
      margin: EdgeInsets.only(
        bottom: 2,
        left: isSubItem ? 16 : 0,
      ), // Indent sub-items
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: isSubItem ? 16 : 20, // Smaller icon for sub-items
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: isSubItem ? FontWeight.w400 : FontWeight.w500,
                    fontSize: isSubItem ? 13 : 14,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (!isSubItem)
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: isDark
                        ? AppColors.darkTextTertiary
                        : AppColors.textTertiary,
                  ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn().slideX(begin: -0.1, end: 0);
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildFooterItem(
            context,
            Iconsax.logout,
            'Logout',
            () {
              context.read<AuthProvider>().logout();
              Navigator.pop(context);
            },
            isDark,
            isDestructive: true,
          ),
          const SizedBox(height: 10),
          Text(
            'Version 1.0.0',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterItem(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
    bool isDark, {
    bool isDestructive = false,
  }) {
    final color = isDestructive
        ? AppColors.error
        : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(
            title,
            style: AppTextStyles.bodyMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
