// HR Policy Screen - displays company HR policies in sectioned cards.
// Section content is placeholder until HR finalises the wording.
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class _PolicySection {
  final String title;
  final String content;
  const _PolicySection(this.title, this.content);
}

class HrPolicyScreen extends StatelessWidget {
  const HrPolicyScreen({super.key});

  static const List<_PolicySection> _sections = [
    _PolicySection(
      '1. Code of Conduct',
      'Employees are expected to maintain the highest standards of professionalism, integrity, and ethical behaviour while representing MECPL. This includes punctuality, respectful communication with colleagues and clients, and adherence to all company guidelines.',
    ),
    _PolicySection(
      '2. Working Hours & Attendance',
      'Standard working hours are as defined in your employment contract. All employees must mark attendance through the MECPL HRMS application using the geofenced punch-in / punch-out facility. Regularization requests must be raised within the timelines specified by HR.',
    ),
    _PolicySection(
      '3. Leave Policy',
      'Leave entitlements (Casual, Sick, Earned, and other categories) are governed by your grade and employment terms. All leave applications must be submitted through the MECPL HRMS Leave module and approved by your reporting manager before being availed, except in case of emergencies.',
    ),
    _PolicySection(
      '4. Anti-Harassment & Equal Opportunity',
      'MECPL is committed to providing a workplace free from harassment and discrimination of any kind. Any incident of harassment — including but not limited to sexual harassment — must be reported immediately to the Internal Complaints Committee (ICC) or HR.',
    ),
    _PolicySection(
      '5. Confidentiality & Data Protection',
      'Employees handling company, client, or employee data must maintain strict confidentiality. Sharing confidential information outside authorised channels, or using it for personal benefit, is a violation of company policy and may attract disciplinary action.',
    ),
    _PolicySection(
      '6. Use of Company Resources',
      'Company-issued devices, accounts, and access credentials are to be used solely for business purposes. Reasonable personal use is permitted but must not interfere with work responsibilities or compromise security.',
    ),
    _PolicySection(
      '7. Travel & Reimbursement',
      'Official travel must be pre-approved by the reporting manager. Reimbursement claims must be submitted with valid bills within the timeline notified by Finance / HR. Daily allowance and travel class entitlements follow the grade-wise policy.',
    ),
    _PolicySection(
      '8. Disciplinary Action',
      'Violation of company policies, code of conduct, or terms of employment may result in disciplinary action ranging from a written warning to termination, depending on the severity and recurrence of the violation.',
    ),
    _PolicySection(
      '9. Grievance Redressal',
      'Any work-related grievance should first be discussed with the immediate reporting manager. If unresolved, it may be escalated to the HR department. MECPL ensures a fair, transparent, and confidential grievance handling process.',
    ),
    _PolicySection(
      '10. Contact HR',
      'For any clarification regarding HR policies, please reach out to the HR department.\n\nMECPL HR Department\nEmail: hr@mecpl.in  |  info.hr@mecpl.in',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text('HR Policy', style: AppTextStyles.headlineLarge),
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
                      Iconsax.book_1,
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
                          'HR Policy',
                          style: AppTextStyles.titleLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Company guidelines & code of conduct',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn().slideY(begin: 0.1, end: 0),

            const SizedBox(height: 24),

            for (int i = 0; i < _sections.length; i++)
              _buildSection(context, isDark, _sections[i], i * 80),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    bool isDark,
    _PolicySection section,
    int delayMs,
  ) {
    return Padding(
          padding: const EdgeInsets.only(bottom: 16),
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
                  section.title,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  section.content,
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
