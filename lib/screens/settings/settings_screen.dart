// Settings Screen - App Configuration
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/biometric_service.dart';
import 'change_password_screen.dart';
import 'terms_of_service_screen.dart';
import 'privacy_policy_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text('Settings', style: AppTextStyles.headlineLarge),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(AppConstants.paddingLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAppearanceSection(context, isDark),
            const SizedBox(height: 24),
            _buildNotificationSection(context, isDark),
            const SizedBox(height: 24),
            _buildSecuritySection(context, isDark),
            const SizedBox(height: 24),
            _buildAboutSection(context, isDark),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Appearance',
          style: AppTextStyles.titleMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusLG),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border,
            ),
          ),
          child: Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return Column(
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        themeProvider.isDarkMode ? Iconsax.moon : Iconsax.sun,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    title: const Text('Dark Mode'),
                    subtitle: Text(themeProvider.isDarkMode ? 'On' : 'Off'),
                    trailing: Switch.adaptive(
                      value: themeProvider.isDarkMode,
                      onChanged: (value) => themeProvider.toggleTheme(),
                      activeThumbColor: AppColors.primary,
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.darkBorder : AppColors.border,
                  ),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Iconsax.colorfilter,
                        color: AppColors.secondary,
                        size: 20,
                      ),
                    ),
                    title: const Text('Accent Color'),
                    subtitle: const Text('Indigo'),
                    trailing: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                    ),
                    onTap: () {},
                  ),
                ],
              );
            },
          ),
        ).animate().fadeIn().slideY(begin: 0.1, end: 0),
      ],
    );
  }

  Widget _buildNotificationSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notifications',
          style: AppTextStyles.titleMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 12),
        Consumer<SettingsProvider>(
          builder: (context, settings, child) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.surface,
                borderRadius: BorderRadius.circular(AppConstants.radiusLG),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                ),
              ),
              child: Column(
                children: [
                  _buildSwitchTile(
                    icon: Iconsax.notification,
                    color: AppColors.primary,
                    title: 'Push Notifications',
                    subtitle: settings.pushNotifications
                        ? 'Enabled'
                        : 'Disabled',
                    value: settings.pushNotifications,
                    onChanged: (value) =>
                        settings.togglePushNotifications(value),
                    isDark: isDark,
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.darkBorder : AppColors.border,
                  ),
                  _buildSwitchTile(
                    icon: Iconsax.sms,
                    color: AppColors.success,
                    title: 'Email Notifications',
                    subtitle: settings.emailNotifications
                        ? 'Enabled'
                        : 'Disabled',
                    value: settings.emailNotifications,
                    onChanged: (value) =>
                        settings.toggleEmailNotifications(value),
                    isDark: isDark,
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.darkBorder : AppColors.border,
                  ),
                  _buildSwitchTile(
                    icon: Iconsax.clock,
                    color: AppColors.warning,
                    title: 'Attendance Reminders',
                    subtitle: settings.attendanceReminders
                        ? 'Enabled'
                        : 'Disabled',
                    value: settings.attendanceReminders,
                    onChanged: (value) =>
                        settings.toggleAttendanceReminders(value),
                    isDark: isDark,
                  ),
                ],
              ),
            );
          },
        ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0),
      ],
    );
  }

  /// Enables or disables biometric login from the settings switch.
  ///
  /// Turning ON: confirms the device has biometric hardware + enrollment,
  /// then triggers a live biometric prompt so the user actually authenticates
  /// once before we flip the flag. Without that confirmation step the user
  /// could brick themselves out of the app with an invalid enrollment.
  ///
  /// Turning OFF: no prompt — just clear the flag.
  Future<void> _toggleBiometric(
    BuildContext context,
    AuthProvider auth,
    bool enable,
  ) async {
    if (!enable) {
      await auth.setBiometricEnabled(false);
      return;
    }
    final available = await BiometricService.instance.isAvailable();
    if (!context.mounted) return;
    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No biometric enrolled on this device. Add a fingerprint or '
            'Face ID in system settings first.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    final ok = await BiometricService.instance.authenticate(
      reason: 'Confirm biometric to enable quick login',
    );
    if (!ok) return;
    await auth.setBiometricEnabled(true);
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.primary,
      ),
    );
  }

  Widget _buildSecuritySection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Security',
          style: AppTextStyles.titleMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 12),
        Consumer<SettingsProvider>(
          builder: (context, settings, child) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.surface,
                borderRadius: BorderRadius.circular(AppConstants.radiusLG),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                ),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Iconsax.lock,
                        color: AppColors.error,
                        size: 20,
                      ),
                    ),
                    title: const Text('Change Password'),
                    trailing: Icon(
                      Iconsax.arrow_right,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.textTertiary,
                      size: 18,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ChangePasswordScreen(),
                        ),
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.darkBorder : AppColors.border,
                  ),
                  // Reads from AuthProvider — this is the flag that actually
                  // gates the BiometricLockScreen on app launch. The old
                  // SettingsProvider.biometricLogin was a dead boolean that
                  // wasn't wired to anything.
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) => _buildSwitchTile(
                      icon: Iconsax.finger_scan,
                      color: AppColors.info,
                      title: 'Biometric Login',
                      subtitle: 'Use fingerprint or face ID',
                      value: auth.isBiometricEnabled,
                      onChanged: (value) =>
                          _toggleBiometric(context, auth, value),
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            );
          },
        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
      ],
    );
  }

  Widget _buildAboutSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About',
          style: AppTextStyles.titleMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusLG),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Iconsax.people,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                title: const Text('MECPL HRMS'),
                subtitle: const Text('Version 1.0.0'),
                trailing: Icon(
                  Iconsax.arrow_right,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.textTertiary,
                  size: 18,
                ),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Iconsax.people,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'MECPL HRMS',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Version 1.0.0',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'MECPL Human Resource Management System',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Developed by MECPL',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '© 2026 MECPL. All rights reserved.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Divider(
                height: 1,
                color: isDark ? AppColors.darkBorder : AppColors.border,
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Iconsax.document_text,
                    color: AppColors.secondary,
                    size: 20,
                  ),
                ),
                title: const Text('Terms of Service'),
                trailing: Icon(
                  Iconsax.arrow_right,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.textTertiary,
                  size: 18,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TermsOfServiceScreen(),
                    ),
                  );
                },
              ),
              Divider(
                height: 1,
                color: isDark ? AppColors.darkBorder : AppColors.border,
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Iconsax.shield_tick,
                    color: AppColors.warning,
                    size: 20,
                  ),
                ),
                title: const Text('Privacy Policy'),
                trailing: Icon(
                  Iconsax.arrow_right,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.textTertiary,
                  size: 18,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PrivacyPolicyScreen(),
                    ),
                  );
                },
              ),
              Divider(
                height: 1,
                color: isDark ? AppColors.darkBorder : AppColors.border,
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Iconsax.message_question,
                    color: AppColors.info,
                    size: 20,
                  ),
                ),
                title: const Text('Help & Support'),
                trailing: Icon(
                  Iconsax.arrow_right,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.textTertiary,
                  size: 18,
                ),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.info.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Iconsax.message_question,
                              color: AppColors.info,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Help & Support',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildSupportRow(
                            icon: Iconsax.sms,
                            title: 'Email',
                            value: 'info.hr@mecpl.in',
                          ),
                          const SizedBox(height: 12),
                          _buildSupportRow(
                            icon: Iconsax.call,
                            title: 'Phone',
                            value: '+91 20 1234 5678',
                          ),
                          const SizedBox(height: 12),
                          _buildSupportRow(
                            icon: Iconsax.clock,
                            title: 'Working Hours',
                            value: 'Mon - Fri, 9 AM - 6 PM',
                          ),
                          const SizedBox(height: 12),
                          _buildSupportRow(
                            icon: Iconsax.location,
                            title: 'Address',
                            value: 'MECPL Office, Pune, India',
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'For any queries or issues, feel free to reach out to our support team.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),
      ],
    );
  }

  Widget _buildSupportRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.info),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
