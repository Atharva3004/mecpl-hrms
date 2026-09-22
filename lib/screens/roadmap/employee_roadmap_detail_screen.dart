// Employee Roadmap detail — a compact, animated career view for one employee.
//
// Sections: header (Name + Designation), Designation Roadmap, Educational
// Details, Previous Experience, Salary Roadmap, and Appraisal History (a mini
// line chart + per-cycle list).
//
// NOTE: Runs on in-memory MOCK data (see `mockRoadmapEmployees`). Swap for an
// ApiService call once the backend exposes a roadmap endpoint.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';

// ─────────────────────────── Models + mock data ───────────────────────────

class DesignationStep {
  final String title;
  final String period; // e.g. "2019 – 2021"
  const DesignationStep(this.title, this.period);
}

class EducationItem {
  final String degree;
  final String institute;
  final String year;
  const EducationItem(this.degree, this.institute, this.year);
}

class ExperienceItem {
  final String company;
  final String role;
  final String duration;
  const ExperienceItem(this.company, this.role, this.duration);
}

class SalaryStep {
  final String year;
  final int amount; // annual / monthly figure
  const SalaryStep(this.year, this.amount);
}

class AppraisalScore {
  final String cycle; // e.g. "2022"
  final double score; // out of 5
  const AppraisalScore(this.cycle, this.score);
}

class EmployeeRoadmap {
  final String name;
  final String empCode;
  final String designation;
  final String department;
  final List<DesignationStep> designationRoadmap;
  final List<EducationItem> education;
  final List<ExperienceItem> previousExperience;
  final List<SalaryStep> salaryRoadmap;
  final List<AppraisalScore> appraisals;
  final int otherBenefits; // current monthly allowances / perks (₹ / month)
  final int ctc; // current cost-to-company (₹ / year)

  const EmployeeRoadmap({
    required this.name,
    required this.empCode,
    required this.designation,
    required this.department,
    required this.designationRoadmap,
    required this.education,
    required this.previousExperience,
    required this.salaryRoadmap,
    required this.appraisals,
    required this.otherBenefits,
    required this.ctc,
  });
}

/// Shared mock list — used by both the picker and this detail screen.
const List<EmployeeRoadmap> mockRoadmapEmployees = [
  EmployeeRoadmap(
    name: 'KAMALESH KUMAR',
    empCode: '30572',
    designation: 'OPERATOR (TOWER CRANE)',
    department: 'MAINTENANCE & ELECTRICAL',
    designationRoadmap: [
      DesignationStep('Trainee Operator', '2018 – 2019'),
      DesignationStep('Operator', '2019 – 2022'),
      DesignationStep('Operator (Tower Crane)', '2022 – Present'),
    ],
    education: [
      EducationItem('ITI – Electrician', 'Govt. ITI, Pune', '2016'),
      EducationItem('HSC (12th)', 'Maharashtra Board', '2014'),
    ],
    previousExperience: [
      ExperienceItem('Skyline Infra', 'Crane Operator', '2 yrs'),
      ExperienceItem('BuildWell Constr.', 'Helper', '1 yr'),
    ],
    salaryRoadmap: [
      SalaryStep('2019', 18000),
      SalaryStep('2021', 24000),
      SalaryStep('2023', 28000),
      SalaryStep('2025', 31000),
    ],
    appraisals: [
      AppraisalScore('2021', 3.4),
      AppraisalScore('2022', 3.8),
      AppraisalScore('2023', 4.1),
      AppraisalScore('2024', 4.5),
    ],
    otherBenefits: 4500,
    ctc: 426000,
  ),
  EmployeeRoadmap(
    name: 'SHIVRAJ INGALE',
    empCode: '30418',
    designation: 'ENGINEER',
    department: 'Q.A',
    designationRoadmap: [
      DesignationStep('Graduate Engineer Trainee', '2020 – 2021'),
      DesignationStep('Jr. Engineer', '2021 – 2023'),
      DesignationStep('Engineer', '2023 – Present'),
    ],
    education: [
      EducationItem('B.E. – Mechanical', 'SPPU, Pune', '2020'),
      EducationItem('Diploma – Mechanical', 'MSBTE', '2017'),
    ],
    previousExperience: [
      ExperienceItem('Precision Tools', 'QA Trainee', '1 yr'),
    ],
    salaryRoadmap: [
      SalaryStep('2021', 26000),
      SalaryStep('2023', 34000),
      SalaryStep('2025', 42000),
    ],
    appraisals: [
      AppraisalScore('2021', 3.6),
      AppraisalScore('2022', 4.0),
      AppraisalScore('2023', 4.3),
      AppraisalScore('2024', 4.6),
    ],
    otherBenefits: 6000,
    ctc: 576000,
  ),
  EmployeeRoadmap(
    name: 'SARVESH KUMAR',
    empCode: '30559',
    designation: 'SUPERVISOR III',
    department: 'CIVIL',
    designationRoadmap: [
      DesignationStep('Site Supervisor', '2017 – 2020'),
      DesignationStep('Supervisor II', '2020 – 2023'),
      DesignationStep('Supervisor III', '2023 – Present'),
    ],
    education: [EducationItem('Diploma – Civil', 'MSBTE', '2016')],
    previousExperience: [
      ExperienceItem('UrbanBuild', 'Site Supervisor', '3 yrs'),
      ExperienceItem('Metro Infra', 'Site Engineer', '2 yrs'),
    ],
    salaryRoadmap: [
      SalaryStep('2018', 22000),
      SalaryStep('2021', 30000),
      SalaryStep('2024', 38000),
    ],
    appraisals: [
      AppraisalScore('2021', 3.2),
      AppraisalScore('2022', 3.5),
      AppraisalScore('2023', 3.9),
      AppraisalScore('2024', 4.2),
    ],
    otherBenefits: 5200,
    ctc: 516000,
  ),
];

// ─────────────────────────────── UI ───────────────────────────────────────

/// One step in a horizontal timeline (designation / salary roadmap).
class _TimelineItem {
  final String title;
  final String subtitle;
  final bool current;
  const _TimelineItem({
    required this.title,
    required this.subtitle,
    required this.current,
  });
}

class EmployeeRoadmapDetailScreen extends StatelessWidget {
  final EmployeeRoadmap emp;
  const EmployeeRoadmapDetailScreen({super.key, required this.emp});

  static final _money = NumberFormat.decimalPattern('en_IN');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Employee Roadmap',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: [
          _header()
              .animate()
              .fadeIn(duration: 350.ms)
              .slideY(begin: 0.12, end: 0),
          const SizedBox(height: 8),
          _animated(0, _educationCard()),
          const SizedBox(height: 8),
          _animated(1, _experienceCard()),
          const SizedBox(height: 8),
          _animated(2, _designationRoadmapCard()),
          const SizedBox(height: 8),
          _animated(3, _salaryRoadmapCard()),
          const SizedBox(height: 8),
          _animated(4, _appraisalCard()),
        ],
      ),
    );
  }

  Widget _animated(int i, Widget child) => child
      .animate()
      .fadeIn(delay: (120 + i * 90).ms, duration: 350.ms)
      .slideY(begin: 0.1, end: 0, delay: (120 + i * 90).ms, duration: 350.ms);

  // ── Header (ID-style card, matching the Employee Summary card) ──
  Widget _header() {
    const darkBlue = Color(0xFF1E3A8A);
    const blue = Color(0xFF2563EB);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top blue banner with title + map icon (straight edge) ──
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [darkBlue, blue],
              ),
            ),
            child: Stack(
              children: [
                // lighter diagonal accent stripe on the right
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: ClipPath(
                    clipper: _AccentClipper(),
                    child: Container(
                      width: 130,
                      color: Colors.white.withOpacity(0.12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Icon(
                          Iconsax.map_1,
                          size: 12,
                          color: blue,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Employee Roadmap',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Body: avatar + name/designation/code, then department ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Initial avatar with blue frame (no photo in roadmap data)
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: blue,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: _avatar(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _cardRow(
                            'Name',
                            emp.name,
                            emphasize: true,
                          ),
                          _cardRow('Designation', emp.designation),
                          _cardRow('Emp Code', emp.empCode),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _cardRow('Department', emp.department),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Letter-initial avatar shown in the blue frame (roadmap has no photo).
  Widget _avatar() {
    final initial = emp.name.isNotEmpty ? emp.name[0].toUpperCase() : '?';
    return Container(
      width: 72,
      height: 84,
      color: AppColors.primary.withOpacity(0.15),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.poppins(
          fontSize: 36,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  /// One "Label : Value" row inside the ID card. Hidden when [value] is blank.
  Widget _cardRow(
    String label,
    String value, {
    bool emphasize = false,
    bool oneLine = false,
  }) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7280),
              ),
            ),
          ),
          Text(
            ':  ',
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              color: const Color(0xFF6B7280),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: oneLine ? 1 : null,
              overflow: oneLine ? TextOverflow.ellipsis : TextOverflow.clip,
              style: GoogleFonts.poppins(
                fontSize: emphasize ? 12.5 : 11,
                fontWeight: emphasize ? FontWeight.bold : FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section scaffold ──
  Widget _section(String title, IconData icon, Color color, Widget body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }

  // ── Designation roadmap (horizontal timeline) ──
  Widget _designationRoadmapCard() {
    return _section(
      'Designation Roadmap',
      Iconsax.hierarchy_square,
      const Color(0xFF6366F1),
      _horizontalTimeline(const Color(0xFF6366F1), [
        for (var i = 0; i < emp.designationRoadmap.length; i++)
          _TimelineItem(
            title: emp.designationRoadmap[i].title,
            subtitle: emp.designationRoadmap[i].period,
            current: i == emp.designationRoadmap.length - 1,
          ),
      ]),
    );
  }

  // ── Educational details ──
  // Show only the latest / highest qualification (most recent year).
  Widget _educationCard() {
    final EducationItem? latest = emp.education.isEmpty
        ? null
        : emp.education.reduce(
            (a, b) => (int.tryParse(b.year) ?? 0) > (int.tryParse(a.year) ?? 0)
                ? b
                : a,
          );
    return _section(
      'Educational Details',
      Iconsax.teacher,
      const Color(0xFF0EA5E9),
      latest == null
          ? _twoLineRow('—', 'No education details available')
          : _twoLineRow(latest.degree, '${latest.institute} · ${latest.year}'),
    );
  }

  // ── Previous experience ──
  Widget _experienceCard() {
    return _section(
      'Previous Experience',
      Iconsax.briefcase,
      const Color(0xFFF59E0B),
      Column(
        children: [
          for (var i = 0; i < emp.previousExperience.length; i++) ...[
            if (i > 0) const Divider(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    '${emp.previousExperience[i].role} · ${emp.previousExperience[i].company}',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  emp.previousExperience[i].duration,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Salary roadmap (horizontal timeline with amounts + growth) ──
  Widget _salaryRoadmapCard() {
    const green = Color(0xFF10B981);
    return _section(
      'Salary Track',
      Iconsax.money_recive,
      green,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _horizontalTimeline(green, [
            for (var i = 0; i < emp.salaryRoadmap.length; i++)
              _TimelineItem(
                title: '₹${_money.format(emp.salaryRoadmap[i].amount)}',
                // Growth % shown in brackets next to the year, e.g. "2021 (33%)".
                subtitle: i == 0
                    ? emp.salaryRoadmap[i].year
                    : '${emp.salaryRoadmap[i].year} '
                          '(${_growthPct(emp.salaryRoadmap[i - 1].amount, emp.salaryRoadmap[i].amount)})',
                current: i == emp.salaryRoadmap.length - 1,
              ),
          ]),
          const SizedBox(height: 12),
          // Expandable dropdown revealing current Other Benefits + CTC.
          _SalaryBenefitsDropdown(
            accent: green,
            otherBenefits: '₹${_money.format(emp.otherBenefits)} / month',
            ctc: '₹${_money.format(emp.ctc)} / year',
          ),
        ],
      ),
    );
  }

  // ── Appraisal history (mini chart + list) ──
  Widget _appraisalCard() {
    final scores = emp.appraisals;
    return _section(
      'Appraisal History (Score)',
      Iconsax.chart_2,
      const Color(0xFFEC4899),
      SizedBox(height: 110, child: _appraisalChart(scores)),
    );
  }

  Widget _appraisalChart(List<AppraisalScore> scores) {
    const pink = Color(0xFFEC4899);
    final barData = LineChartBarData(
      spots: [
        for (var i = 0; i < scores.length; i++)
          FlSpot(i.toDouble(), scores[i].score),
      ],
      isCurved: true,
      curveSmoothness: 0.3,
      color: pink,
      barWidth: 3,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
          radius: 3.5,
          color: Colors.white,
          strokeWidth: 2,
          strokeColor: pink,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [pink.withOpacity(0.22), pink.withOpacity(0.01)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
    return LineChart(
      LineChartData(
        // Scores never fall below ~3, so start the axis at 2.5 and drop the
        // 0/1/2 gridlines + labels — the chart uses its full height for 3–5.
        minY: 2.5,
        // Headroom above the 3–5 range so the score labels sit clear above the
        // top dots instead of overlapping the line.
        maxY: 6,
        // Always-on tooltips render each year's score above its dot.
        lineTouchData: LineTouchData(
          enabled: false,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 8,
            fitInsideVertically: true,
            fitInsideHorizontally: true,
            getTooltipItems: (touchedSpots) => touchedSpots
                .map(
                  (s) => LineTooltipItem(
                    s.y.toStringAsFixed(1),
                    GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: pink,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        showingTooltipIndicators: [
          for (var i = 0; i < barData.spots.length; i++)
            ShowingTooltipIndicators([
              LineBarSpot(barData, 0, barData.spots[i]),
            ]),
        ],
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          // Only draw the 3, 4, 5 lines; the 6 line is just headroom.
          checkToShowHorizontalLine: (v) => v >= 3 && v <= 5,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 22,
              getTitlesWidget: (v, _) {
                // Show only 3, 4, 5 — the 0/1/2 labels are dropped and the 6 is
                // just headroom for the score tags.
                if (v < 3 || v > 5) return const SizedBox.shrink();
                return Text(
                  v.toInt().toString(),
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    color: AppColors.textTertiary,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= scores.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    scores[i].cycle,
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      color: AppColors.textTertiary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [barData],
      ),
    );
  }

  // ── Small shared widgets ──

  // Horizontal timeline: dots in a row connected left-to-right, scrollable.
  Widget _horizontalTimeline(Color color, List<_TimelineItem> items) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            SizedBox(
              width: 90,
              child: Column(
                children: [
                  // connector line + dot
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i == 0
                              ? Colors.transparent
                              : color.withOpacity(0.25),
                        ),
                      ),
                      Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: items[i].current ? color : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 2),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i == items.length - 1
                              ? Colors.transparent
                              : color.withOpacity(0.25),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      children: [
                        Text(
                          items[i].title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: items[i].current
                                ? color
                                : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          items[i].subtitle,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _twoLineRow(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }

  /// Growth from [prev] to [curr] as a signed percent string, e.g. "33%".
  String _growthPct(int prev, int curr) {
    final pct = prev == 0 ? 0 : ((curr - prev) / prev * 100).round();
    return '$pct%';
  }
}

/// A tap-to-expand dropdown inside the Salary Track card. Collapsed it shows a
/// single "View CTC & Benefits" row with a chevron; expanded it reveals the
/// current Other Benefits and CTC figures.
class _SalaryBenefitsDropdown extends StatefulWidget {
  final Color accent;
  final String otherBenefits;
  final String ctc;

  const _SalaryBenefitsDropdown({
    required this.accent,
    required this.otherBenefits,
    required this.ctc,
  });

  @override
  State<_SalaryBenefitsDropdown> createState() =>
      _SalaryBenefitsDropdownState();
}

class _SalaryBenefitsDropdownState extends State<_SalaryBenefitsDropdown> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Container(
      decoration: BoxDecoration(
        color: accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tappable header row
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Iconsax.wallet_3, size: 14, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    'CTC & Other Benefits',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: 200.ms,
                    child: Icon(
                      Iconsax.arrow_down_1,
                      size: 15,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expanding body
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(height: 12, color: accent.withOpacity(0.15)),
                  _benefitRow('OTHER BENEFITS', widget.otherBenefits, accent),
                  const SizedBox(height: 8),
                  _benefitRow('CTC', widget.ctc, accent),
                ],
              ),
            ),
            crossFadeState:
                _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: 220.ms,
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }

  Widget _benefitRow(String label, String value, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: GoogleFonts.poppins(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ),
      ],
    );
  }
}

/// A slanted parallelogram used as a lighter accent stripe on the banner.
class _AccentClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.45, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.1, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
