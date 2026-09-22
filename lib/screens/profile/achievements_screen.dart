import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';

import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../models/leave_balance_model.dart';
import '../../models/leave_application_model.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  bool _isLoading = true;

  // Leave data
  List<LeaveBalance> _leaveBalances = [];
  List<LeaveApplication> _leaveHistory = [];

  // Calculated stats
  double _totalLeaves = 0;
  double _usedLeaves = 0;
  double _remainingLeaves = 0;
  double _leaveUtilization = 0; // percentage
  int _approvedCount = 0;
  int _rejectedCount = 0;
  int _totalApplications = 0;
  int _currentStreak = 0; // consecutive months with low leave usage

  // Attendance stats
  int _totalPresentDays = 0;
  int _totalAbsentDays = 0;
  int _totalHalfDays = 0;
  int _totalOnTimeDays = 0;
  int _longestPresentStreak = 0;
  int _totalWorkingDays = 0;
  double _attendancePercentage = 0;
  double _onTimePercentage = 0;

  // Badges
  List<Map<String, dynamic>> _unlockedBadges = [];
  List<Map<String, dynamic>> _lockedBadges = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    final empId = auth.currentUser?.id ?? auth.currentUser?.employeeId ?? '';

    if (token == null || token.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final results = await Future.wait([
        ApiService.getLeaveBalance(token: token, empId: empId),
        ApiService.getLeaveHistory(token: token, empId: empId),
      ]);

      _leaveBalances = results[0] as List<LeaveBalance>;
      _leaveHistory = results[1] as List<LeaveApplication>;

      // Fetch Attendance (Calendar Data) for the year
      final now = DateTime.now();
      final currentYear = now.year.toString();
      final monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
      
      List<Future<ApiResponse>> calendarFutures = [];
      for (int i = 0; i < now.month; i++) {
        calendarFutures.add(
          ApiService.getCalendarData(
            token: token,
            month: monthNames[i],
            year: currentYear,
          )
        );
      }
      
      final calendarResults = await Future.wait(calendarFutures);
      Map<String, Map<String, dynamic>> allAttendance = {};
      
      for (var response in calendarResults) {
        if (response.isSuccess && response.data != null) {
          final data = response.data!;
          if (data['success'] == true && data['attendanceData'] != null) {
            final Map<String, dynamic> rawAttendance = data['attendanceData'];
            rawAttendance.forEach((key, value) {
              allAttendance[key] = Map<String, dynamic>.from(value);
            });
          }
        }
      }

      _calculateStats();
      _calculateAttendanceStats(allAttendance);
      _calculateBadges();
    } catch (e) {
      debugPrint('Error loading achievements data: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _calculateStats() {
    // Leave balance stats
    _totalLeaves = 0;
    _usedLeaves = 0;
    for (final lb in _leaveBalances) {
      _totalLeaves += lb.balance;
      _usedLeaves += lb.used;
    }
    _remainingLeaves = _totalLeaves - _usedLeaves;
    _leaveUtilization = _totalLeaves > 0 ? (_usedLeaves / _totalLeaves) * 100 : 0;

    // Leave application stats
    _totalApplications = _leaveHistory.length;
    _approvedCount = _leaveHistory.where((l) => l.status.toLowerCase() == 'approved').length;
    _rejectedCount = _leaveHistory.where((l) => l.status.toLowerCase() == 'rejected').length;

    // Calculate streak: months in current year with <= 1 leave
    final now = DateTime.now();
    int streak = 0;
    for (int m = now.month; m >= 1; m--) {
      final leavesInMonth = _leaveHistory.where((l) {
        return l.fromDate.month == m && l.fromDate.year == now.year && l.status.toLowerCase() == 'approved';
      }).fold<double>(0, (sum, l) => sum + l.netLeaveDays);
      if (leavesInMonth <= 1) {
        streak++;
      } else {
        break;
      }
    }
    _currentStreak = streak;
  }

  void _calculateAttendanceStats(Map<String, Map<String, dynamic>> allAttendance) {
    int totalPresent = 0;
    int totalAbsent = 0;
    int totalHalfDay = 0;
    int totalOnTime = 0;
    int currentStreak = 0;
    int longestStreak = 0;
    int workingDays = 0;

    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);

    final sortedKeys = allAttendance.keys.toList()..sort();
    
    for (var key in sortedKeys) {
      if (key.compareTo(todayKey) > 0) continue;

      final dayData = allAttendance[key]!;
      final status = dayData['status']?.toString().toLowerCase() ?? '';
      final isLate = (dayData['late'] ?? 0) == 1;

      if (status == 'wo' || status == 'ph') {
         // Non-working days don't break the streak or count for attendance percentage
         continue;
      }

      workingDays++;
      
      if (status == 'p') {
        totalPresent++;
        currentStreak++;
        if (currentStreak > longestStreak) {
          longestStreak = currentStreak;
        }
        if (!isLate) {
          totalOnTime++;
        }
      } else if (status == 'a') {
        totalAbsent++;
        currentStreak = 0;
      } else if (status == 'hd') {
        totalHalfDay++;
        currentStreak = 0;
      } else if (status == 'l') {
        currentStreak = 0;
      }
    }

    _totalPresentDays = totalPresent;
    _totalAbsentDays = totalAbsent;
    _totalHalfDays = totalHalfDay;
    _totalOnTimeDays = totalOnTime;
    _longestPresentStreak = longestStreak;
    _totalWorkingDays = workingDays;

    _attendancePercentage = _totalWorkingDays > 0 ? (_totalPresentDays / _totalWorkingDays) * 100 : 0.0;
    _onTimePercentage = _totalPresentDays > 0 ? (_totalOnTimeDays / _totalPresentDays) * 100 : 0.0;
  }

  void _calculateBadges() {
    _unlockedBadges = [];
    _lockedBadges = [];

    // Badge: Perfect Attendance — 0 leaves used
    if (_usedLeaves == 0) {
      _unlockedBadges.add({
        'name': 'Perfect Attendance 🏅',
        'desc': 'Zero leaves taken this year',
        'icon': Iconsax.medal_star,
        'color': const Color(0xFFEAB308),
        'sparkle': true,
      });
    } else {
      _lockedBadges.add({
        'name': 'Perfect Attendance 🏅',
        'desc': 'Take zero leaves in a year',
        'icon': Iconsax.medal_star,
        'color': Colors.grey,
        'sparkle': false,
      });
    }

    // Badge: Leave Saver — < 30% leave utilization
    if (_totalLeaves > 0 && _leaveUtilization < 30) {
      _unlockedBadges.add({
        'name': 'Leave Saver 💰',
        'desc': 'Less than 30% leaves used',
        'icon': Iconsax.wallet_3,
        'color': const Color(0xFF10B981),
        'sparkle': true,
      });
    } else {
      _lockedBadges.add({
        'name': 'Leave Saver 💰',
        'desc': 'Use less than 30% of your leaves',
        'icon': Iconsax.wallet_3,
        'color': Colors.grey,
        'sparkle': false,
      });
    }

    // Badge: Consistent — streak >= 3 months
    if (_currentStreak >= 3) {
      _unlockedBadges.add({
        'name': 'Consistent 🔥',
        'desc': '$_currentStreak months with minimal leave',
        'icon': Iconsax.flash,
        'color': const Color(0xFFF97316),
        'sparkle': true,
      });
    } else {
      _lockedBadges.add({
        'name': 'Consistent 🔥',
        'desc': '3+ months with ≤1 leave/month',
        'icon': Iconsax.flash,
        'color': Colors.grey,
        'sparkle': false,
      });
    }

    // Badge: Punctual — all leave applications approved (100% approval rate)
    if (_totalApplications > 0 && _rejectedCount == 0) {
      _unlockedBadges.add({
        'name': 'Punctual ⏰',
        'desc': '100% leave approval rate',
        'icon': Iconsax.verify,
        'color': const Color(0xFF6366F1),
        'sparkle': false,
      });
    } else {
      _lockedBadges.add({
        'name': 'Punctual ⏰',
        'desc': 'Get 100% leave approval rate',
        'icon': Iconsax.verify,
        'color': Colors.grey,
        'sparkle': false,
      });
    }

    // Badge: Team Player — no half-day leaves, only full days
    final hasHalfDays = _leaveHistory.any((l) => l.halfDay.toLowerCase() != 'full day' && l.halfDay != '0');
    if (_totalApplications > 0 && !hasHalfDays) {
      _unlockedBadges.add({
        'name': 'Team Player 🤝',
        'desc': 'Only full-day leaves taken',
        'icon': Iconsax.profile_2user,
        'color': const Color(0xFF0EA5E9),
        'sparkle': false,
      });
    } else {
      _lockedBadges.add({
        'name': 'Team Player 🤝',
        'desc': 'Take only full-day leaves',
        'icon': Iconsax.profile_2user,
        'color': Colors.grey,
        'sparkle': false,
      });
    }

    // Badge: First Leave — at least 1 leave application
    if (_totalApplications >= 1) {
      _unlockedBadges.add({
        'name': 'First Leave 📋',
        'desc': 'Applied for your first leave',
        'icon': Iconsax.document_text,
        'color': const Color(0xFF8B5CF6),
        'sparkle': false,
      });
    } else {
      _lockedBadges.add({
        'name': 'First Leave 📋',
        'desc': 'Apply for your first leave',
        'icon': Iconsax.document_text,
        'color': Colors.grey,
        'sparkle': false,
      });
    }

    // Badge: Iron Man — used >= 90% of total leaves (work hard, rest hard)
    if (_totalLeaves > 0 && _leaveUtilization >= 90) {
      _unlockedBadges.add({
        'name': 'Well Rested 😊',
        'desc': 'Used 90%+ of your leaves',
        'icon': Iconsax.sun,
        'color': const Color(0xFFEC4899),
        'sparkle': false,
      });
    } else {
      _lockedBadges.add({
        'name': 'Well Rested 😊',
        'desc': 'Use 90%+ of your leaves',
        'icon': Iconsax.sun,
        'color': Colors.grey,
        'sparkle': false,
      });
    }

    // Badge: Dedicated — streak >= 6 months
    if (_currentStreak >= 6) {
      _unlockedBadges.add({
        'name': 'Dedicated 💎',
        'desc': '6+ months with minimal leave',
        'icon': Iconsax.award,
        'color': const Color(0xFF14B8A6),
        'sparkle': true,
      });
    } else {
      _lockedBadges.add({
        'name': 'Dedicated 💎',
        'desc': '6+ months with ≤1 leave/month',
        'icon': Iconsax.award,
        'color': Colors.grey,
        'sparkle': false,
      });
    }

    // Attendance Badge: Iron Will — 30+ consecutive present days
    if (_longestPresentStreak >= 30) {
      _unlockedBadges.add({
        'name': 'Iron Will 💪',
        'desc': '30+ consecutive present days',
        'icon': Iconsax.shield_tick,
        'color': const Color(0xFFEAB308),
        'sparkle': true,
      });
    } else {
      _lockedBadges.add({
        'name': 'Iron Will 💪',
        'desc': '30+ consecutive present days',
        'icon': Iconsax.shield_tick,
        'color': Colors.grey,
        'sparkle': false,
      });
    }

    // Attendance Badge: Early Bird — 90%+ on-time rate
    if (_totalPresentDays > 0 && _onTimePercentage >= 90) {
      _unlockedBadges.add({
        'name': 'Early Bird 🐦',
        'desc': '90%+ on-time punctuality rate',
        'icon': Iconsax.sun_1,
        'color': const Color(0xFFF97316),
        'sparkle': true,
      });
    } else {
      _lockedBadges.add({
        'name': 'Early Bird 🐦',
        'desc': '90%+ on-time punctuality rate',
        'icon': Iconsax.sun_1,
        'color': Colors.grey,
        'sparkle': false,
      });
    }

    // Attendance Badge: Centurion — 100+ total present days
    if (_totalPresentDays >= 100) {
      _unlockedBadges.add({
        'name': 'Centurion 💯',
        'desc': '100+ total present days this year',
        'icon': Iconsax.crown,
        'color': const Color(0xFF6366F1),
        'sparkle': true,
      });
    } else {
      _lockedBadges.add({
        'name': 'Centurion 💯',
        'desc': '100+ total present days this year',
        'icon': Iconsax.crown,
        'color': Colors.grey,
        'sparkle': false,
      });
    }

    // Attendance Badge: No Absence — zero absents
    if (_totalWorkingDays > 0 && _totalAbsentDays == 0) {
      _unlockedBadges.add({
        'name': 'No Absence 🎯',
        'desc': 'Zero absent days this year',
        'icon': Iconsax.shield_cross,
        'color': const Color(0xFF10B981),
        'sparkle': true,
      });
    } else {
      _lockedBadges.add({
        'name': 'No Absence 🎯',
        'desc': 'Maintain zero absent days',
        'icon': Iconsax.shield_cross,
        'color': Colors.grey,
        'sparkle': false,
      });
    }

    // Attendance Badge: Half-Day Free — zero half-days
    if (_totalWorkingDays > 0 && _totalHalfDays == 0) {
      _unlockedBadges.add({
        'name': 'Half-Day Free 🌟',
        'desc': 'Zero half-days this year',
        'icon': Iconsax.star,
        'color': const Color(0xFF0EA5E9),
        'sparkle': false,
      });
    } else {
      _lockedBadges.add({
        'name': 'Half-Day Free 🌟',
        'desc': 'Take zero half-days',
        'icon': Iconsax.star,
        'color': Colors.grey,
        'sparkle': false,
      });
    }

    // Attendance Badge: Attendance Pro — 95%+ attendance
    if (_totalWorkingDays > 0 && _attendancePercentage >= 95) {
      _unlockedBadges.add({
        'name': 'Attendance Pro 📊',
        'desc': '95%+ overall attendance',
        'icon': Iconsax.chart_success,
        'color': const Color(0xFF8B5CF6),
        'sparkle': false,
      });
    } else {
      _lockedBadges.add({
        'name': 'Attendance Pro 📊',
        'desc': 'Achieve 95%+ overall attendance',
        'icon': Iconsax.chart_success,
        'color': Colors.grey,
        'sparkle': false,
      });
    }
  }

  // Calculate XP and level from achievements
  int get _xp {
    int xp = 0;
    xp += _unlockedBadges.length * 100; // each badge = 100 XP
    xp += (_approvedCount * 10); // each approved leave = 10 XP
    xp += (_currentStreak * 50); // each streak month = 50 XP
    if (_remainingLeaves > 0) xp += (_remainingLeaves * 5).toInt(); // remaining leaves bonus
    
    // Attendance XP
    xp += (_totalPresentDays * 5);     // 5 XP per present day
    xp += (_totalOnTimeDays * 3);      // 3 XP per on-time day
    xp += (_longestPresentStreak * 20); // 20 XP per streak day
    
    return xp;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(context, isDark),
          SliverToBoxAdapter(child: _buildQuickStats(isDark)),

          // Attendance Summary
          SliverToBoxAdapter(child: _buildAttendanceSummarySection(isDark)),

          // Leave Balance Summary
          SliverToBoxAdapter(child: _buildLeaveBalanceSection(isDark)),

          // Unlocked Badges
          if (_unlockedBadges.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text('Unlocked Badges', style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.bold)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: _buildBadgesGrid(isDark, badges: _unlockedBadges, unlocked: true),
            ),
          ],

          // Locked Badges
          if (_lockedBadges.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Text('Coming Soon', style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.bold)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: _buildBadgesGrid(isDark, badges: _lockedBadges, unlocked: false),
            ),
          ],

          // Milestones
          SliverToBoxAdapter(child: _buildMilestones(isDark)),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isDark) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      surfaceTintColor: Colors.transparent,
      title: Text(
        'My Achievements 🏆',
        style: AppTextStyles.headlineLarge.copyWith(color: isDark ? Colors.white : AppColors.textPrimary),
      ),
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Icon(Icons.chevron_left, color: isDark ? Colors.white : AppColors.textPrimary),
      ),
    );
  }



  Widget _buildQuickStats(bool isDark) {
    String streakLabel = _currentStreak > _longestPresentStreak ? '$_currentStreak mo' : '$_longestPresentStreak d';
    final stats = [
      {'label': 'Badges', 'value': '${_unlockedBadges.length}', 'icon': Iconsax.medal},
      {'label': 'Streak', 'value': streakLabel, 'icon': Iconsax.flash},
      {'label': 'Attendance', 'value': '${_attendancePercentage.toStringAsFixed(0)}%', 'icon': Iconsax.activity},
      {'label': 'XP', 'value': '$_xp', 'icon': Iconsax.star},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: stats.asMap().entries.map((entry) {
          final index = entry.key;
          final stat = entry.value;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: index < stats.length - 1 ? 12 : 0),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10))],
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
              ),
              child: Column(
                children: [
                  Icon(stat['icon'] as IconData, color: AppColors.primary, size: 24),
                  const SizedBox(height: 12),
                  Text(stat['value'] as String, style: AppTextStyles.titleLarge.copyWith(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.textPrimary)),
                  Text(stat['label'] as String, style: AppTextStyles.caption.copyWith(fontSize: 10), textAlign: TextAlign.center),
                ],
              ),
            ).animate(delay: (200 + index * 100).ms).fadeIn().slideY(begin: 0.2, end: 0),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAttendanceSummarySection(bool isDark) {
    if (_totalWorkingDays == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
          boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Attendance Summary', style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildMiniStat('Present', '$_totalPresentDays', const Color(0xFF10B981), isDark),
                const SizedBox(width: 8),
                _buildMiniStat('Absent', '$_totalAbsentDays', const Color(0xFFF43F5E), isDark),
                const SizedBox(width: 8),
                _buildMiniStat('Half Day', '$_totalHalfDays', const Color(0xFFF59E0B), isDark),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Overall Attendance', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                Text('${_attendancePercentage.toStringAsFixed(0)}%', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF10B981))),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: (_attendancePercentage / 100).clamp(0.0, 1.0),
                backgroundColor: const Color(0xFF10B981).withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation(
                  _attendancePercentage < 75 ? const Color(0xFFF43F5E) : _attendancePercentage < 90 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                ),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Punctuality (On-Time)', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                Text('${_onTimePercentage.toStringAsFixed(0)}%', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF6366F1))),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: (_onTimePercentage / 100).clamp(0.0, 1.0),
                backgroundColor: const Color(0xFF6366F1).withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation(
                  _onTimePercentage < 80 ? const Color(0xFFF59E0B) : const Color(0xFF6366F1),
                ),
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildLeaveBalanceSection(bool isDark) {
    if (_leaveBalances.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
          boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Leave Summary', style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            // Overall stats row
            Row(
              children: [
                _buildMiniStat('Total', '${_totalLeaves.toStringAsFixed(0)}', const Color(0xFF6366F1), isDark),
                const SizedBox(width: 8),
                _buildMiniStat('Used', '${_usedLeaves.toStringAsFixed(0)}', const Color(0xFFF43F5E), isDark),
                const SizedBox(width: 8),
                _buildMiniStat('Remaining', '${_remainingLeaves.toStringAsFixed(0)}', const Color(0xFF10B981), isDark),
              ],
            ),
            const SizedBox(height: 14),
            // Utilization bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Leave Utilization', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                Text('${_leaveUtilization.toStringAsFixed(0)}%', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: _leaveUtilization / 100,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation(
                  _leaveUtilization > 80 ? const Color(0xFFF43F5E) : _leaveUtilization > 50 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                ),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 14),
            // Per leave-type breakdown
            ..._leaveBalances.map((lb) {
              final pct = lb.balance > 0 ? (lb.used / lb.balance) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(lb.leaveType.leaveName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      flex: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct.clamp(0.0, 1.0),
                          backgroundColor: Colors.grey.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation(pct > 0.8 ? const Color(0xFFF43F5E) : const Color(0xFF6366F1)),
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${lb.used.toStringAsFixed(0)}/${lb.balance.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildMiniStat(String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 9, color: color.withOpacity(0.7), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgesGrid(bool isDark, {required List<Map<String, dynamic>> badges, required bool unlocked}) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final badge = badges[index];
        final color = badge['color'] as Color;
        final isSparkle = badge['sparkle'] as bool;

        Widget badgeIcon = Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: unlocked ? color.withOpacity(0.1) : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant),
            shape: BoxShape.circle,
            border: Border.all(color: unlocked ? color.withOpacity(0.3) : Colors.transparent, width: 2),
            boxShadow: [
              if (unlocked && isSparkle) BoxShadow(color: color.withOpacity(0.2), blurRadius: 15, spreadRadius: 2),
            ],
          ),
          child: Center(child: Icon(badge['icon'] as IconData, color: unlocked ? color : Colors.grey.withOpacity(0.5), size: 28)),
        ).animate(delay: (index * 50).ms).scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)).fadeIn();

        if (unlocked && isSparkle) {
          badgeIcon = badgeIcon.animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds, color: Colors.white54);
        }

        return GestureDetector(
          onTap: () => _showBadgeDetail(context, badge, unlocked, isDark),
          child: Column(
            children: [
              badgeIcon,
              const SizedBox(height: 8),
              Text(
                badge['name'] as String,
                style: AppTextStyles.caption.copyWith(
                  fontWeight: unlocked ? FontWeight.w600 : FontWeight.normal,
                  color: unlocked ? (isDark ? Colors.white : AppColors.textPrimary) : Colors.grey,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }, childCount: badges.length),
    );
  }

  void _showBadgeDetail(BuildContext context, Map<String, dynamic> badge, bool unlocked, bool isDark) {
    final color = badge['color'] as Color;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (unlocked ? color : Colors.grey).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(badge['icon'] as IconData, color: unlocked ? color : Colors.grey, size: 40),
            ),
            const SizedBox(height: 16),
            Text(badge['name'] as String, style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              badge['desc'] as String,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: unlocked ? const Color(0xFF10B981).withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                unlocked ? '✅ Unlocked' : '🔒 Locked',
                style: TextStyle(
                  color: unlocked ? const Color(0xFF10B981) : Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestones(bool isDark) {
    // Dynamic milestones based on real data
    final milestones = <Map<String, dynamic>>[];

    // Milestone: Use all leaves
    if (_totalLeaves > 0) {
      milestones.add({
        'title': 'Leave Master',
        'desc': 'Manage all your leave days wisely',
        'progress': _totalLeaves > 0 ? (_usedLeaves / _totalLeaves).clamp(0.0, 1.0) : 0.0,
        'target': '${_usedLeaves.toStringAsFixed(0)}/${_totalLeaves.toStringAsFixed(0)} days',
        'icon': Iconsax.calendar_tick,
        'color': AppColors.primary,
      });
    }

    // Milestone: Get all leaves approved
    if (_totalApplications > 0) {
      final approvalRate = _totalApplications > 0 ? _approvedCount / _totalApplications : 0.0;
      milestones.add({
        'title': '100% Approval',
        'desc': 'Get all your leave applications approved',
        'progress': approvalRate.clamp(0.0, 1.0),
        'target': '$_approvedCount/$_totalApplications approved',
        'icon': Iconsax.tick_circle,
        'color': AppColors.success,
      });
    }

    // Milestone: 6-month streak
    milestones.add({
      'title': 'Half-Year Streak',
      'desc': '6 consecutive months with minimal leave (≤1/month)',
      'progress': (_currentStreak / 6).clamp(0.0, 1.0),
      'target': '$_currentStreak/6 months',
      'icon': Iconsax.flash,
      'color': const Color(0xFFF97316),
    });

    // Milestone: Attendance Champion
    if (_totalWorkingDays > 0) {
      milestones.add({
        'title': 'Attendance Champion',
        'desc': 'Achieve 95% attendance rate',
        'progress': (_attendancePercentage / 95).clamp(0.0, 1.0),
        'target': '${_attendancePercentage.toStringAsFixed(0)}%/95%',
        'icon': Iconsax.verify,
        'color': const Color(0xFF8B5CF6),
      });
    }

    // Milestone: Punctuality Master
    if (_totalPresentDays > 0) {
      milestones.add({
        'title': 'Punctuality Master',
        'desc': 'Achieve 90% on-time arrival',
        'progress': (_onTimePercentage / 90).clamp(0.0, 1.0),
        'target': '${_onTimePercentage.toStringAsFixed(0)}%/90%',
        'icon': Iconsax.clock,
        'color': const Color(0xFFF97316),
      });
    }

    // Milestone: 50-Day Present Streak
    milestones.add({
      'title': 'Unstoppable',
      'desc': '50 consecutive present days',
      'progress': (_longestPresentStreak / 50).clamp(0.0, 1.0),
      'target': '$_longestPresentStreak/50 days',
      'icon': Iconsax.shield_tick,
      'color': const Color(0xFF10B981),
    });

    if (milestones.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Milestones', style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...milestones.asMap().entries.map((entry) {
            final m = entry.value;
            final color = m['color'] as Color;
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                    child: Icon(m['icon'] as IconData, color: color, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(m['title'] as String, style: AppTextStyles.titleSmall.copyWith(fontWeight: FontWeight.bold)),
                            Text(m['target'] as String, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(m['desc'] as String, style: AppTextStyles.caption),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: m['progress'] as double,
                            backgroundColor: color.withOpacity(0.1),
                            valueColor: AlwaysStoppedAnimation(color),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate(delay: (400 + entry.key * 100).ms).fadeIn().slideX(begin: 0.1, end: 0);
          }),
        ],
      ),
    );
  }
}
