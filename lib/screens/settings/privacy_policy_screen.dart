// Privacy Policy Screen
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text('Privacy Policy', style: AppTextStyles.headlineLarge),
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
            // Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppConstants.radiusLG),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Iconsax.shield_tick,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Privacy Policy',
                          style: AppTextStyles.titleLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Last updated: March 2026',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn().slideY(begin: 0.1, end: 0),

            const SizedBox(height: 24),

            _buildSection(
              context,
              isDark,
              '1. Information We Collect',
              'We collect information you provide directly, including your name, employee ID, contact details, attendance data, leave records, and payroll information. We also automatically collect device information, app usage data, and location data (for attendance purposes only) when you use the MECPL HRMS application.',
              0,
            ),
            _buildSection(
              context,
              isDark,
              '2. How We Use Your Information',
              'Your information is used to:\n• Manage employee attendance and leave records\n• Process payroll and generate payslips\n• Facilitate HR operations and communications\n• Improve app performance and user experience\n• Comply with legal and regulatory requirements\n• Ensure workplace safety and security',
              100,
            ),
            _buildSection(
              context,
              isDark,
              '3. Data Storage & Security',
              'Your data is stored on secure servers with industry-standard encryption. We implement appropriate technical and organizational measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction. Access to employee data is restricted to authorized HR personnel and management.',
              200,
            ),
            _buildSection(
              context,
              isDark,
              '4. Data Sharing',
              'We do not sell or rent your personal information to third parties. Your data may be shared with:\n• Authorized company management and HR personnel\n• Government agencies as required by law\n• Third-party service providers who assist in app operations (bound by confidentiality agreements)',
              300,
            ),
            _buildSection(
              context,
              isDark,
              '5. Your Rights',
              'You have the right to:\n• Access your personal data stored in the system\n• Request correction of inaccurate information\n• Request information about how your data is used\n• Raise concerns about data handling with the HR department\n\nTo exercise these rights, contact your HR representative.',
              400,
            ),
            _buildSection(
              context,
              isDark,
              '6. Data Retention',
              'Employee data is retained for the duration of your employment and for a period as required by applicable labor laws and company policies after the end of employment. Attendance and payroll records are maintained as per statutory requirements.',
              500,
            ),
            _buildSection(
              context,
              isDark,
              '7. Cookies & Tracking',
              'The MECPL HRMS application may use local storage and session tokens to maintain your login state and preferences. These are essential for the functioning of the application and cannot be disabled while using the service.',
              600,
            ),
            _buildSection(
              context,
              isDark,
              '8. Changes to This Policy',
              'We may update this Privacy Policy from time to time. Any changes will be communicated through the application. Your continued use of the app after changes are posted constitutes your acceptance of the revised policy.',
              700,
            ),
            _buildSection(
              context,
              isDark,
              '9. Contact Us',
              'If you have questions or concerns about this Privacy Policy or our data practices, please contact:\n\nMECPL HR Department\nEmail: info.hr@mecpl.in',
              800,
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    bool isDark,
    String title,
    String content,
    int delayMs,
  ) {
    return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusLG),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(delay: Duration(milliseconds: delayMs))
        .slideY(begin: 0.05, end: 0);
  }
}
