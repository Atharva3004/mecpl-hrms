// Terms of Service Screen
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text('Terms of Service', style: AppTextStyles.headlineLarge),
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
                      Iconsax.document_text,
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
                          'Terms of Service',
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
              '1. Acceptance of Terms',
              'By accessing and using the MECPL HRMS application, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the application.',
              0,
            ),
            _buildSection(
              context,
              isDark,
              '2. Use of the Application',
              'The MECPL HRMS application is provided for authorized employees and personnel of MECPL and its affiliated entities. You agree to use the application solely for legitimate human resource management purposes, including but not limited to attendance tracking, leave management, payroll viewing, and document access.',
              100,
            ),
            _buildSection(
              context,
              isDark,
              '3. User Accounts',
              'You are responsible for maintaining the confidentiality of your login credentials. You must not share your account information with others. Any activity that occurs under your account is your responsibility. Notify the administrator immediately if you suspect unauthorized access to your account.',
              200,
            ),
            _buildSection(
              context,
              isDark,
              '4. Data Accuracy',
              'You agree to provide accurate and up-to-date information when using the application. This includes, but is not limited to, attendance records, leave applications, and personal information updates. Intentional submission of false information may result in disciplinary action.',
              300,
            ),
            _buildSection(
              context,
              isDark,
              '5. Intellectual Property',
              'The MECPL HRMS application, including all content, features, and functionality, is owned by MECPL and is protected by applicable intellectual property laws. You may not copy, modify, distribute, or create derivative works based on the application without prior written consent.',
              400,
            ),
            _buildSection(
              context,
              isDark,
              '6. Limitation of Liability',
              'MECPL shall not be liable for any indirect, incidental, special, consequential, or punitive damages resulting from your use of or inability to use the application. MECPL does not warrant that the application will be uninterrupted, error-free, or completely secure.',
              500,
            ),
            _buildSection(
              context,
              isDark,
              '7. Modifications',
              'MECPL reserves the right to modify these Terms of Service at any time. Changes will be communicated through the application. Your continued use of the application after such modifications constitutes acceptance of the updated terms.',
              600,
            ),
            _buildSection(
              context,
              isDark,
              '8. Contact',
              'For questions or concerns regarding these Terms of Service, please contact the HR department or reach out to info.hr@mecpl.in.',
              700,
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
