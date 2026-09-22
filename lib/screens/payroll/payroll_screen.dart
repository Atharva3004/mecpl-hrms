// Payroll Screen - Salary & Payslips
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../../widgets/common/custom_loader.dart';
import '../../widgets/common/logo_loader.dart';

class PayrollScreen extends StatefulWidget {
  final UserModel? user;
  const PayrollScreen({super.key, this.user});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  int _selectedMonth = DateTime.now().month - 1;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final currentUser = auth.currentUser;
        final displayUser = widget.user ?? currentUser;

        if (displayUser == null) {
          return const Scaffold(
            body: Center(child: CustomLoader(size: 60)),
          );
        }

        final isOwnPayroll =
            widget.user == null || widget.user?.id == currentUser?.id;

        return Scaffold(
          backgroundColor: isDark
              ? AppColors.darkBackground
              : AppColors.background,
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // App Bar
                SliverAppBar(
                  pinned: true,
                  backgroundColor: isDark
                      ? AppColors.darkBackground
                      : AppColors.background,
                  surfaceTintColor: Colors.transparent,
                  leading: ModalRoute.of(context)?.canPop == true
                      ? IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.chevron_left),
                        )
                      : null,
                  title: Text(
                    isOwnPayroll ? 'My Payroll' : 'Employee Payroll',
                    style: AppTextStyles.headlineLarge,
                  ),
                  actions: [
                    IconButton(
                      onPressed: () =>
                          _handleDownload(context, 'November 2024'),
                      icon: const Icon(Iconsax.document_download),
                    ),
                  ],
                ),

                if (!isOwnPayroll)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: AppColors.primary.withOpacity(0.1),
                            child: Text(
                              displayUser.initials,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Viewing: ${displayUser.fullName}',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(),
                  ),

                // Salary Summary Card
                SliverToBoxAdapter(child: _buildSalarySummary(isDark)),

                // Month Selector
                SliverToBoxAdapter(child: _buildMonthSelector(isDark)),

                // Salary Breakdown Chart
                SliverToBoxAdapter(child: _buildSalaryBreakdown(isDark)),

                // Payslip Details
                SliverToBoxAdapter(child: _buildPayslipDetails(isDark)),

                // Recent Payslips
                SliverToBoxAdapter(child: _buildRecentPayslips(isDark)),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleDownload(BuildContext context, String month) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LogoLoader(width: 150, height: 150),
              const SizedBox(height: 24),
              Text(
                    'Generating Payslip...',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: Colors.white,
                    ),
                  )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fadeIn(duration: 800.ms),
            ],
          ),
        ),
      ),
    );

    // Mock download delay
    await Future.delayed(2000.ms);
    if (!mounted) return;
    Navigator.pop(context);

    // Show professional success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Iconsax.tick_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Payslip for $month downloaded successfully!',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'OPEN',
          textColor: Colors.white,
          onPressed: () {
            // Mock open action
          },
        ),
      ),
    );
  }

  Widget _buildSalarySummary(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.paddingLG),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              'Net Salary',
              style: AppTextStyles.bodyMedium.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              '₹75,450',
              style: AppTextStyles.displayLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text(
                'November 2024 • Paid on Dec 1',
                style: AppTextStyles.labelSmall.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ).animate().fadeIn().slideY(begin: -0.2, end: 0),
    );
  }

  Widget _buildMonthSelector(bool isDark) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingLG),
        itemCount: months.length,
        itemBuilder: (context, index) {
          final isSelected = index == _selectedMonth;
          return GestureDetector(
            onTap: () => setState(() => _selectedMonth = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : isDark
                    ? AppColors.darkSurface
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                border: isSelected
                    ? null
                    : Border.all(
                        color: isDark ? AppColors.darkBorder : AppColors.border,
                      ),
              ),
              child: Text(
                months[index],
                style: AppTextStyles.labelMedium.copyWith(
                  color: isSelected
                      ? Colors.white
                      : isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildSalaryBreakdown(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.paddingLG),
      child: Container(
        padding: const EdgeInsets.all(20),
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
              'Salary Breakdown',
              style: AppTextStyles.titleMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: [
                    PieChartSectionData(
                      value: 65,
                      title: '65%',
                      color: AppColors.primary,
                      radius: 50,
                      titleStyle: AppTextStyles.labelSmall.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      value: 20,
                      title: '20%',
                      color: AppColors.secondary,
                      radius: 50,
                      titleStyle: AppTextStyles.labelSmall.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      value: 10,
                      title: '10%',
                      color: AppColors.warning,
                      radius: 50,
                      titleStyle: AppTextStyles.labelSmall.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      value: 5,
                      title: '5%',
                      color: AppColors.error,
                      radius: 50,
                      titleStyle: AppTextStyles.labelSmall.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildLegend(),
          ],
        ),
      ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),
    );
  }

  Widget _buildLegend() {
    final items = [
      {'label': 'Basic', 'color': AppColors.primary, 'value': '₹50,000'},
      {'label': 'Allowances', 'color': AppColors.secondary, 'value': '₹15,000'},
      {'label': 'Bonus', 'color': AppColors.warning, 'value': '₹8,000'},
      {'label': 'Deductions', 'color': AppColors.error, 'value': '₹4,550'},
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: item['color'] as Color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${item['label']}: ${item['value']}',
              style: AppTextStyles.bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildPayslipDetails(bool isDark) {
    final earnings = [
      {'label': 'Basic Salary', 'value': '₹50,000'},
      {'label': 'House Rent Allowance', 'value': '₹8,000'},
      {'label': 'Transport Allowance', 'value': '₹3,000'},
      {'label': 'Medical Allowance', 'value': '₹2,000'},
      {'label': 'Special Allowance', 'value': '₹2,000'},
      {'label': 'Performance Bonus', 'value': '₹8,000'},
    ];

    final deductions = [
      {'label': 'Provident Fund', 'value': '₹2,000'},
      {'label': 'Professional Tax', 'value': '₹200'},
      {'label': 'Income Tax', 'value': '₹2,350'},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingLG),
      child: Container(
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Earnings',
                style: AppTextStyles.titleMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            ...earnings.map(
              (item) => _buildDetailRow(
                item['label']!,
                item['value']!,
                isDark,
                false,
              ),
            ),
            Divider(color: isDark ? AppColors.darkBorder : AppColors.border),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Deductions',
                style: AppTextStyles.titleMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            ...deductions.map(
              (item) =>
                  _buildDetailRow(item['label']!, item['value']!, isDark, true),
            ),
            Divider(color: isDark ? AppColors.darkBorder : AppColors.border),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Net Pay',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    '₹75,450',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(delay: 400.ms),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    bool isDark,
    bool isDeduction,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              color: isDeduction ? AppColors.error : AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentPayslips(bool isDark) {
    final payslips = [
      {'month': 'October 2024', 'amount': '₹74,200', 'status': 'Paid'},
      {'month': 'September 2024', 'amount': '₹73,800', 'status': 'Paid'},
      {'month': 'August 2024', 'amount': '₹75,000', 'status': 'Paid'},
    ];

    return Padding(
      padding: const EdgeInsets.all(AppConstants.paddingLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Previous Payslips',
            style: AppTextStyles.titleLarge.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          ...payslips.asMap().entries.map((entry) {
            final index = entry.key;
            final payslip = entry.value;

            return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                    border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Iconsax.receipt,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              payslip['month']!,
                              style: AppTextStyles.titleSmall.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              payslip['status']!,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        payslip['amount']!,
                        style: AppTextStyles.titleSmall.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () =>
                            _handleDownload(context, payslip['month']!),
                        icon: Icon(
                          Iconsax.document_download,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                )
                .animate(delay: Duration(milliseconds: 100 * index))
                .fadeIn()
                .slideX(begin: 0.1, end: 0);
          }),
        ],
      ),
    );
  }
}
