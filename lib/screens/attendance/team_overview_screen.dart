import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../models/user_model.dart';
import '../../models/role_model.dart';
import '../../widgets/common/custom_loader.dart';

class TeamOverviewScreen extends StatefulWidget {
  const TeamOverviewScreen({super.key});

  /// Roles allowed to see employees across departments. Anyone NOT in this
  /// set is department-scoped (sees only their own department).
  static const Set<UserRole> crossDepartmentRoles = {
    UserRole.director,
    UserRole.admin,
  };

  /// Trims a department string for case/whitespace-insensitive comparison.
  /// `null` and empty strings normalise to `null` so they never match.
  static String? normaliseDept(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    return s.isEmpty ? null : s;
  }

  /// Whether the dashboard / drawer should expose the Team Overview entry to
  /// this user. Returns false for department-scoped roles with no department
  /// set — they would land on an empty list, so the entry is hidden entirely.
  /// Director and Admin always qualify.
  static bool canAccessTeamOverview(UserModel? user) {
    if (user == null) return false;
    if (crossDepartmentRoles.contains(user.role)) return true;
    return normaliseDept(user.department) != null;
  }

  @override
  State<TeamOverviewScreen> createState() => _TeamOverviewScreenState();
}

class _TeamOverviewScreenState extends State<TeamOverviewScreen> {
  DateTime _selectedDateObj = DateTime.now();
  late String _selectedDate;
  int? _expandedIndex;
  
  String _selectedStatus = 'Present';
  int? _selectedBranchId;
  List<dynamic> _branches = [];
  bool _isLoadingBranches = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateFormat('yyyy-MM-dd').format(_selectedDateObj);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initData();
    });
  }
  
  Future<void> _initData() async {
    final authProvider = context.read<AuthProvider>();
    final role = authProvider.currentRole;
    final user = authProvider.currentUser;

    // Admin logic: fetch branches
    if (role == UserRole.admin || role == UserRole.director || role == UserRole.hrAdmin) {
      setState(() => _isLoadingBranches = true);
      try {
        _branches = await ApiService.getBranches(authProvider.token ?? '');
        // Default to the Head Office (HO) branch so the first load is scoped —
        // fetching every branch's attendance is slow. Falls back to
        // "All Branches" if HO isn't found.
        _selectedBranchId ??= _defaultBranchId(_branches);
      } catch (e) {
        print("Error fetching branches: $e");
      }
      setState(() => _isLoadingBranches = false);
    }
    // On-site admin: restrict to own branch
    else if (role == UserRole.onSiteAdmin) {
      if (user?.branchId != null) {
        _selectedBranchId = user!.branchId;
      }
    }

    _fetchTeamData();
  }

  /// Returns the id of the Head Office (HO) branch if present, else null so the
  /// filter stays on "All Branches".
  int? _defaultBranchId(List<dynamic> branches) {
    for (final b in branches) {
      final name = (b.branchName ?? '').toString().trim().toLowerCase();
      if (name == 'ho' || name == 'head office' || name.contains('head office')) {
        return b.id as int?;
      }
    }
    return null;
  }

  void _fetchTeamData() {
    final authProvider = context.read<AuthProvider>();
    final provider = context.read<AttendanceProvider>();
    final token = authProvider.token ?? '';

    provider.fetchTeamAttendance(
      token: token,
      date: _selectedDate,
      branchId: _selectedBranchId?.toString(),
    );
  }

  /// Two-stage filter for the team list:
  ///   1. Hide Director rows from anyone who isn't a Director (privacy).
  ///   2. Department-scope users not in [TeamOverviewScreen.crossDepartmentRoles] — they only
  ///      see employees whose department matches their own.
  /// Both filters are client-side. For stricter confidentiality the backend
  /// should also enforce these rules on `/get_daily_attendance`.
  List<UserModel> _filterTeamForViewer(List<UserModel> raw) {
    final auth = context.read<AuthProvider>();
    final viewer = auth.currentUser;
    final viewerRole = auth.currentRole;
    var team = raw;

    // (1) Hide directors from non-directors.
    if (viewerRole != UserRole.director) {
      team = team.where((u) => u.role != UserRole.director).toList();
    }

    // (2) Department-scope non-privileged roles.
    if (viewer != null && !TeamOverviewScreen.crossDepartmentRoles.contains(viewerRole)) {
      final viewerDept = TeamOverviewScreen.normaliseDept(viewer.department);
      if (viewerDept == null) {
        // Manager / HR mid-level with no department set — show nothing.
        // The Team Overview entry should already have been hidden via
        // canAccessTeamOverview, but if the user landed here anyway
        // (deep-link, cached navigator) we still don't leak data.
        return const <UserModel>[];
      }
      team = team
          .where((u) => TeamOverviewScreen.normaliseDept(u.department) == viewerDept)
          .toList();
    }

    return team;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Team Overview",
          style: GoogleFonts.poppins(
            color: const Color.fromARGB(255, 0, 0, 0),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterBar(isDark),
          _buildStatusFilter(isDark),
          _buildTableHeader(isDark),
          // Thin progress bar shown only when the provider is reloading AND
          // we have cached data to keep on screen. Same pattern as
          // EmployeeLeaveSummaryScreen — avoids a blank flash when the user
          // changes date / branch / status filters.
          Consumer<AttendanceProvider>(
            builder: (context, p, _) {
              final showInline =
                  p.isLoading && p.teamAttendance.isNotEmpty;
              return AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: showInline
                    ? LinearProgressIndicator(
                        minHeight: 2,
                        backgroundColor:
                            AppColors.primary.withOpacity(0.1),
                        valueColor:
                            AlwaysStoppedAnimation(AppColors.primary),
                      )
                    : const SizedBox(height: 0),
              );
            },
          ),
          Expanded(child: _buildTeamList(isDark)),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    final authProvider = context.watch<AuthProvider>();
    final role = authProvider.currentRole;
    final bool isAdmin = role == UserRole.admin || role == UserRole.director || role == UserRole.hrAdmin;
    final bool isOnSiteAdmin = role == UserRole.onSiteAdmin;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // Date Filter
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDateObj.isBefore(AppConstants.appStartDate)
                      ? AppConstants.appStartDate
                      : _selectedDateObj,
                  firstDate: AppConstants.appStartDate,
                  lastDate: DateTime(2100),
                );
                if (date != null) {
                  setState(() {
                    _selectedDateObj = date;
                    _selectedDate = DateFormat('yyyy-MM-dd').format(date);
                  });
                  _fetchTeamData();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: isDark ? Colors.white70 : Colors.indigo),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        DateFormat('dd MMM').format(_selectedDateObj),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 12, 
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          if (isAdmin || isOnSiteAdmin) const SizedBox(width: 12),

          // Branch Filter
          if (isAdmin) 
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
                ),
                child: _isLoadingBranches 
                  ? const Center(child: CustomLoader(size: 20))
                  : DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        value: _selectedBranchId,
                        hint: Text(
                          'All Branches', 
                          style: GoogleFonts.poppins(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87)
                        ),
                        icon: Icon(Icons.keyboard_arrow_down, size: 16, color: isDark ? Colors.white70 : Colors.black87),
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'All Branches', 
                              style: GoogleFonts.poppins(fontSize: 12, color: isDark ? Colors.white : Colors.black87)
                            ),
                          ),
                          ..._branches.map((b) {
                            return DropdownMenuItem<int?>(
                              value: b.id,
                              child: Text(
                                b.branchName, 
                                overflow: TextOverflow.ellipsis, 
                                style: GoogleFonts.poppins(fontSize: 12, color: isDark ? Colors.white : Colors.black87)
                              ),
                            );
                          }).toList(),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedBranchId = val;
                          });
                          _fetchTeamData();
                        },
                      ),
                    ),
              )
            )
          else if (isOnSiteAdmin)
             Expanded(
              flex: 3,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_city, size: 16, color: isDark ? Colors.white54 : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your Branch',
                        style: GoogleFonts.poppins(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusFilter(bool isDark) {
    final provider = context.watch<AttendanceProvider>();
    // Hide directors from non-director viewers BEFORE computing counts —
    // otherwise the status badges (Present/Absent counts) would still leak
    // the fact that a director exists.
    final team = _filterTeamForViewer(provider.teamAttendance);

    // Compute real counts from team attendance data
    final int presentCount = team.where((u) {
      final s = (u.status ?? '').toUpperCase();
      return s == 'P' || s == 'PRESENT';
    }).length;
    final int absentCount = team.where((u) {
      final s = (u.status ?? '').toUpperCase();
      return s == 'A' || s == 'ABSENT';
    }).length;
    final int halfDayCount = team.where((u) {
      final s = (u.status ?? '').toUpperCase();
      return s == 'HD' || s == 'HALF DAY';
    }).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _buildStatusBadge(
            'All',
            team.length.toString(),
            Colors.black87,
            Colors.grey[200],
          ),
          const SizedBox(width: 6),
          _buildStatusBadge(
            'Present',
            presentCount.toString(),
            Colors.green,
            Colors.green[50],
          ),
          const SizedBox(width: 6),
          _buildStatusBadge(
            'Half Day',
            halfDayCount.toString(),
            Colors.blue,
            Colors.blue[50],
          ),
          const SizedBox(width: 6),
          _buildStatusBadge(
            'Absent',
            absentCount.toString(),
            Colors.red,
            Colors.red[50],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(
    String label,
    String? count,
    Color? color,
    Color? bgColor,
  ) {
    final isSelected = _selectedStatus == label;
    return GestureDetector(
      onTap: () {
         setState(() => _selectedStatus = label);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? bgColor : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  color: Colors.black87,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(5),
                  bottomRight: Radius.circular(5),
                ),
                border: Border(left: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Text(
                count ?? '0',
                style: GoogleFonts.poppins(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // color: const Color(0xFFFBB03B), // Orange/Yellow header
        color: Color.fromARGB(255, 100, 112, 243),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              "Name",
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              "Date",
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              "Status",
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 24), // Space for chevron
        ],
      ),
    );
  }

  Widget _buildTeamList(bool isDark) {
    final provider = context.watch<AttendanceProvider>();
    // Same filter as the status badges — keeps the list and the counts in sync.
    List<UserModel> displayUsers =
        _filterTeamForViewer(provider.teamAttendance);

    // Department-scoped user with no department on their profile — entry
    // should have been hidden, but defensively show a clearer empty state.
    final viewer = context.read<AuthProvider>().currentUser;
    final viewerRole = context.read<AuthProvider>().currentRole;
    final isDeptScoped =
        viewer != null && !TeamOverviewScreen.crossDepartmentRoles.contains(viewerRole);
    final missingDept =
        isDeptScoped && TeamOverviewScreen.normaliseDept(viewer.department) == null;

    if (_selectedBranchId != null) {
      displayUsers = displayUsers.where((u) => u.branchId == _selectedBranchId).toList();
    }

    if (_selectedStatus != 'All') {
      displayUsers = displayUsers.where((u) {
        final s = (u.status ?? '').toUpperCase();
        if (_selectedStatus == 'Present') return s == 'P' || s == 'PRESENT';
        if (_selectedStatus == 'Absent') return s == 'A' || s == 'ABSENT';
        if (_selectedStatus == 'Half Day') return s == 'HD' || s == 'HALF DAY';
        return true;
      }).toList();
    }

    if (provider.isLoading && displayUsers.isEmpty) {
      return const Center(child: CustomLoader(size: 60));
    }

    if (missingDept) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline,
                size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            Text(
              "Department isn't set on your profile",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Please contact HR to update your profile so you can see your team here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    if (displayUsers.isEmpty) {
      return Center(
        child: Text(
          "No attendance records found.",
          style: GoogleFonts.poppins(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      physics: const BouncingScrollPhysics(),
      itemCount: displayUsers.length,
      itemBuilder: (context, index) {
        final user = displayUsers[index];
        final String statusLabel = user.status ?? "P";
        final String displayDate = DateFormat(
          'dd MMM',
        ).format(DateTime.parse(_selectedDate));
        final bool isExpanded = _expandedIndex == index;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey[100]!),
          ),
          child: Column(
            children: [
              // Main row
              GestureDetector(
                onTap: () {
                  setState(() {
                    _expandedIndex = isExpanded ? null : index;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          user.fullName,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          displayDate,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [_buildSmallStatusBadge(statusLabel)],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: const Color(0xFF3F51B5),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),

              // Expanded details panel
              if (isExpanded)
                _buildExpandedDetails(user),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExpandedDetails(UserModel user) {
    final shift = user.designation?.isNotEmpty == true ? user.designation! : 'General';
    final actualInTime = user.firstIn ?? 'NA';
    final actualOutTime = user.lastOut ?? 'NA';
    final shiftInTime = '09:00';
    final shiftOutTime = '18:00';

    final workHours = user.totalWorkHours ?? 'NA';

    // Determine late/early status
    String lateEarlyLabel = '--';
    final s = (user.status ?? '').toUpperCase();
    if (s == 'HD') {
      lateEarlyLabel = 'HD';
    } else if (s == 'A' || s == 'ABSENT') {
      lateEarlyLabel = 'A';
    } else if (s == 'P' || s == 'PRESENT') {
      lateEarlyLabel = '--';
    } else {
      lateEarlyLabel = s.isNotEmpty ? s : '--';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FA),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _buildDetailItem('SHIFT', shift)),
                Expanded(child: _buildDetailItem('SHIFT IN TIME', shiftInTime)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildDetailItem('ACTUAL IN TIME', actualInTime)),
                Expanded(child: _buildDetailItem('SHIFT OUT TIME', shiftOutTime)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildDetailItem('ACTUAL OUT TIME', actualOutTime)),
                Expanded(child: _buildDetailItem('WORK HOURS', workHours)),
              ],
            ),
            const SizedBox(height: 8),
            _buildDetailItem('LATE EARLY', lateEarlyLabel),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
            letterSpacing: 0.3,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildSmallStatusBadge(String label) {
    final s = label.toUpperCase();
    Color textColor;
    Color bgColor;

    switch (s) {
      case 'P':
      case 'PRESENT':
        textColor = const Color(0xFF4CAF50);
        bgColor = const Color(0xFFE8F5E9);
        break;
      case 'A':
      case 'ABSENT':
        textColor = const Color(0xFFE53935);
        bgColor = const Color(0xFFFFEBEE);
        break;
      case 'HD':
      case 'HALF DAY':
        textColor = const Color(0xFFFF9800);
        bgColor = const Color(0xFFFFF3E0);
        break;
      default: // MIS or unknown
        textColor = Colors.orange.shade300;
        bgColor = const Color(0xFFFFF3E0);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}
