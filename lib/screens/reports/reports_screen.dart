// Reports Screen - Analytics & Reports
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/navigation_provider.dart';
import '../attendance/attendance_screen.dart';
import '../payroll/payroll_screen.dart';
import '../leave/leave_screen.dart';
import '../../widgets/common/custom_loader.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _isDownloading = false;

  void _downloadReport(String title) async {
    if (_isDownloading) return;

    setState(() => _isDownloading = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const CustomLoader(size: 20, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Preparing $title...', style: GoogleFonts.poppins()),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );

    // Simulate download delay
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _isDownloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Iconsax.tick_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$title downloaded successfully!',
                  style: GoogleFonts.poppins(),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // App Bar
          SliverAppBar(
            pinned: true,
            backgroundColor: isDark
                ? AppColors.darkBackground
                : AppColors.background,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(
                Icons.chevron_left,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  Provider.of<NavigationProvider>(
                    context,
                    listen: false,
                  ).setIndex(0);
                }
              },
            ),
            title: Text(
              'Reports',
              style: AppTextStyles.headlineLarge.copyWith(
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            actions: [
              // IconButton(
              //   onPressed: () {},
              //   icon: Icon(Iconsax.filter, color: isDark ? Colors.white : AppColors.textPrimary),
              // ),
            ],
          ),

          // Report Categories
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Report Categories',
                    style: AppTextStyles.titleLarge.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildReportCategoriesGrid(context, isDark),
                ],
              ),
            ),
          ),

          // Analytics Overview
          SliverToBoxAdapter(child: _buildAnalyticsOverview(isDark)),

          // Attendance Analytics
          SliverToBoxAdapter(child: _buildAttendanceChart(isDark)),

          // Department Distribution
          SliverToBoxAdapter(child: _buildDepartmentChart(isDark)),

          // Recent Reports
          SliverToBoxAdapter(child: _buildRecentReports(isDark)),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildReportCategoriesGrid(BuildContext context, bool isDark) {
    final categories = [
      {
        'title': 'Attendance',
        'icon': Iconsax.calendar,
        'color': AppColors.primary,
        'gradient': AppColors.primaryGradient,
      },
      {
        'title': 'Payroll',
        'icon': Iconsax.wallet,
        'color': AppColors.success,
        'gradient': AppColors.successGradient,
      },
      {
        'title': 'Leave',
        'icon': Iconsax.calendar_remove,
        'color': AppColors.warning,
        'gradient': AppColors.accentGradient,
      },
      {
        'title': 'Performance',
        'icon': Iconsax.chart_success,
        'color': AppColors.secondary,
        'gradient': AppColors.secondaryGradient,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.3,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final cat = categories[index];
        return GestureDetector(
          onTap: () {
            switch (cat['title'] as String) {
              case 'Attendance':
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AttendanceScreen(),
                  ),
                );
                break;
              case 'Payroll':
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PayrollScreen(),
                  ),
                );
                break;
              case 'Leave':
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LeaveScreen()),
                );
                break;
              case 'Performance':
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Performance reports coming soon!'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                break;
            }
          },
          child:
              Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: cat['gradient'] as LinearGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: (cat['color'] as Color).withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            cat['icon'] as IconData,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          cat['title'] as String,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                  .animate(delay: Duration(milliseconds: 100 * index))
                  .fadeIn()
                  .scale(
                    begin: const Offset(0.9, 0.9),
                    end: const Offset(1, 1),
                  ),
        );
      },
    );
  }

  Widget _buildAnalyticsOverview(bool isDark) {
    final stats = [
      {
        'label': 'Total Employees',
        'value': '248',
        'change': '+12',
        'isPositive': true,
        'icon': Iconsax.people,
        'color': AppColors.primary,
      },
      {
        'label': 'Avg. Attendance',
        'value': '94.2%',
        'change': '+2.4%',
        'isPositive': true,
        'icon': Iconsax.timer,
        'color': AppColors.success,
      },
      {
        'label': 'Leave Rate',
        'value': '5.8%',
        'change': '-0.3%',
        'isPositive': true,
        'icon': Iconsax.calendar_remove,
        'color': AppColors.warning,
      },
      {
        'label': 'Overtime Hours',
        'value': '156h',
        'change': '+18h',
        'isPositive': false,
        'icon': Iconsax.clock,
        'color': AppColors.error,
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Analytics',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 110,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: stats.length,
              itemBuilder: (context, index) {
                final stat = stats[index];
                final color = stat['color'] as Color;
                return Container(
                      width: 160,
                      margin: EdgeInsets.only(
                        right: index < stats.length - 1 ? 12 : 0,
                      ),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurface
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: color.withOpacity(0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  stat['icon'] as IconData,
                                  color: color,
                                  size: 16,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (stat['isPositive'] as bool
                                              ? AppColors.success
                                              : AppColors.error)
                                          .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  stat['change'] as String,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: stat['isPositive'] as bool
                                        ? AppColors.success
                                        : AppColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stat['value'] as String,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                stat['label'] as String,
                                style: AppTextStyles.caption.copyWith(
                                  fontSize: 11,
                                  color: isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                    .animate(delay: Duration(milliseconds: 100 * index))
                    .fadeIn()
                    .slideX(begin: 0.2, end: 0);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceChart(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Attendance Analytics',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceVariant
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('This Week', style: AppTextStyles.labelSmall),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 100,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
                          if (value >= 0 && value < days.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                days[value.toInt()],
                                style: AppTextStyles.caption.copyWith(
                                  fontSize: 10,
                                ),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barGroups: [
                    _buildBarGroup(0, 92, 8),
                    _buildBarGroup(1, 95, 5),
                    _buildBarGroup(2, 88, 12),
                    _buildBarGroup(3, 94, 6),
                    _buildBarGroup(4, 91, 9),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Present', AppColors.primary),
                const SizedBox(width: 24),
                _buildLegendItem(
                  'Absent/Leave',
                  AppColors.error.withOpacity(0.5),
                ),
              ],
            ),
          ],
        ),
      ).animate().fadeIn(delay: 300.ms),
    );
  }

  BarChartGroupData _buildBarGroup(int x, double present, double absent) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: present + absent,
          width: 20,
          borderRadius: BorderRadius.circular(6),
          rodStackItems: [
            BarChartRodStackItem(0, present, AppColors.primary),
            BarChartRodStackItem(
              present,
              present + absent,
              AppColors.error.withOpacity(0.5),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.caption.copyWith(fontSize: 11)),
      ],
    );
  }

  Widget _buildDepartmentChart(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Department Distribution',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            ...[
              'Engineering',
              'Operations',
              'HR',
              'Finance',
              'Marketing',
            ].asMap().entries.map((entry) {
              final index = entry.key;
              final dept = entry.value;
              final values = [45, 28, 12, 10, 5];
              final colors = [
                AppColors.primary,
                AppColors.secondary,
                AppColors.warning,
                AppColors.info,
                AppColors.success,
              ];

              return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              dept,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${values[index]}%',
                              style: AppTextStyles.labelMedium.copyWith(
                                color: colors[index],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: values[index] / 100,
                            backgroundColor: isDark
                                ? AppColors.darkSurfaceVariant
                                : AppColors.surfaceVariant,
                            valueColor: AlwaysStoppedAnimation(colors[index]),
                            minHeight: 10,
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
      ).animate().fadeIn(delay: 400.ms),
    );
  }

  Widget _buildRecentReports(bool isDark) {
    final reports = [
      {
        'title': 'Monthly Attendance Report',
        'date': 'Dec 1, 2024',
        'type': 'Attendance',
        'icon': Iconsax.calendar,
        'color': AppColors.primary,
      },
      {
        'title': 'Payroll Summary - Nov',
        'date': 'Nov 30, 2024',
        'type': 'Payroll',
        'icon': Iconsax.wallet,
        'color': AppColors.success,
      },
      {
        'title': 'Leave Analysis Q4',
        'date': 'Nov 28, 2024',
        'type': 'Leave',
        'icon': Iconsax.calendar_remove,
        'color': AppColors.warning,
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Reports',
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(onPressed: () {}, child: const Text('View All')),
            ],
          ),
          const SizedBox(height: 12),
          ...reports.asMap().entries.map((entry) {
            final index = entry.key;
            final report = entry.value;
            final color = report['color'] as Color;

            return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.border,
                    ),
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          report['icon'] as IconData,
                          color: color,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              report['title'] as String,
                              style: AppTextStyles.titleSmall.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${report['type']} • ${report['date']}',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            _downloadReport(report['title'] as String),
                        icon: const Icon(Iconsax.document_download, size: 20),
                        color: AppColors.textTertiary,
                        visualDensity: VisualDensity.compact,
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
