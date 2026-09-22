import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/api_service.dart';
import 'employee_onboarding_detail_screen.dart';

// Data Model parsed from API
class OnboardingRequest {
  final String id;
  final String empId;
  final String dbId;
  final String name;
  final String designation;
  final String department;
  final String branch;
  final DateTime joinDate;
  final String level;
  final String salary;
  final String? empImageUrl;
  final DateTime? dob;
  final String experience;

  /// Approval levels that have ALREADY approved this onboarding (e.g. [1, 2]).
  /// Parsed defensively from the API response — see [_parseApprovedLevels].
  final List<int> approvedLevels;

  /// The raw JSON object for this employee, kept so the detail screen can read
  /// extra nested sections (personal/bank/education/family/emergency) without
  /// bloating this model with dozens of fields.
  final Map<String, dynamic> raw;

  OnboardingRequest({
    required this.id,
    required this.empId,
    required this.dbId,
    required this.name,
    required this.designation,
    required this.department,
    required this.branch,
    required this.joinDate,
    required this.level,
    required this.salary,
    this.empImageUrl,
    this.dob,
    this.experience = '',
    this.approvedLevels = const [],
    this.raw = const {},
  });

  static const String _empImageBaseUrl =
      'https://hrms.mecpl.in/files/employee/';

  factory OnboardingRequest.fromJson(
    Map<String, dynamic> json, {
    String level = '1',
  }) {
    // Parse employee name
    final name =
        json['emp_name']?.toString() ?? json['name']?.toString() ?? 'Unknown';

    // company_details wraps designation / department / branch / doj / emp_code
    final companyDetails = json['company_details'] is Map<String, dynamic>
        ? json['company_details'] as Map<String, dynamic>
        : const <String, dynamic>{};

    // Designation — prefer nested company_details, fallback to top-level
    String designation = '';
    final desgObj = companyDetails['designation'] ?? json['designation'];
    if (desgObj is Map) {
      designation = desgObj['designation_name']?.toString() ?? '';
    } else {
      designation = desgObj?.toString() ?? '';
    }

    // Department
    String department = '';
    final deptObj = companyDetails['department'] ?? json['department'];
    if (deptObj is Map) {
      department = deptObj['department_name']?.toString() ?? '';
    } else {
      department = deptObj?.toString() ?? '';
    }

    // Branch
    String branch = '';
    final branchObj = companyDetails['branch'] ?? json['branch'];
    if (branchObj is Map) {
      branch = branchObj['branch_name']?.toString() ?? '';
    } else {
      branch = branchObj?.toString() ?? '';
    }

    // Date of Joining
    final rawDoj = (companyDetails['doj'] ??
            json['doj'] ??
            json['joining_date'] ??
            '')
        .toString();
    final joinDate = DateTime.tryParse(rawDoj) ?? DateTime.now();

    // Employee code (HR-facing, e.g., "30444") — used for display
    final rawEmpId = (companyDetails['emp_code'] ??
            json['emp_code'] ??
            '')
        .toString();

    // Database primary key (e.g., 2914) — required by the approval API
    final rawDbId =
        (json['id'] ?? json['emp_id'] ?? companyDetails['id'] ?? '0').toString();

    // Fall back to dbId for display if emp_code isn't present
    final displayEmpId = rawEmpId.isNotEmpty ? rawEmpId : rawDbId;

    // Salary from salary_details.gross_salary
    String salary = '';
    final salaryDetails = json['salary_details'];
    if (salaryDetails is Map) {
      final gross = salaryDetails['gross_salary']?.toString();
      if (gross != null && gross.isNotEmpty) salary = gross;
    }
    if (salary.isEmpty) {
      salary = (json['gross_salary'] ?? json['salary'] ?? '').toString();
    }

    // Personal details may be nested under 'personal_details'
    final personalDetails = json['personal_details'] is Map<String, dynamic>
        ? json['personal_details'] as Map<String, dynamic>
        : const <String, dynamic>{};

    // Date of Birth
    final rawDob = (personalDetails['dob'] ??
            json['dob'] ??
            json['date_of_birth'] ??
            '')
        .toString();
    final dob = rawDob.isNotEmpty ? DateTime.tryParse(rawDob) : null;

    // Experience (years)
    final experience = (personalDetails['prev_experience'] ??
            json['prev_experience'] ??
            json['experience'] ??
            json['total_experience'] ??
            '')
        .toString();

    // emp_image — resolve to full URL if only a filename is provided
    final rawImage = json['emp_image']?.toString() ?? '';
    String? empImageUrl;
    if (rawImage.isNotEmpty) {
      empImageUrl = rawImage.startsWith('http')
          ? rawImage
          : '$_empImageBaseUrl$rawImage';
    }

    return OnboardingRequest(
      id: '#EMP$displayEmpId',
      empId: displayEmpId,
      dbId: rawDbId,
      name: name,
      designation: designation,
      department: department,
      branch: branch,
      joinDate: joinDate,
      level: level,
      salary: salary,
      empImageUrl: empImageUrl,
      dob: dob,
      experience: experience,
      approvedLevels: _parseApprovedLevels(json),
      raw: json,
    );
  }

  int? get age {
    if (dob == null) return null;
    final now = DateTime.now();
    int years = now.year - dob!.year;
    if (now.month < dob!.month ||
        (now.month == dob!.month && now.day < dob!.day)) {
      years -= 1;
    }
    return years >= 0 ? years : null;
  }

  String get formattedDob =>
      dob == null ? '—' : DateFormat('dd MMM yyyy').format(dob!);

  String get formattedJoinDate => DateFormat('dd MMM yyyy').format(joinDate);

  String get formattedAge => age == null ? '—' : '${age!} yrs';

  String get formattedExperience {
    if (experience.isEmpty) return '—';
    final value = num.tryParse(experience);
    if (value == null) return experience;
    return '${value % 1 == 0 ? value.toInt() : value} yrs';
  }

  String get formattedSalary {
    if (salary.isEmpty) return '—';
    final value = double.tryParse(salary);
    if (value == null) return salary;
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    return formatter.format(value);
  }

  /// Salary normalised per year of experience (gross salary ÷ experience).
  /// "Fresher" when experience is 0/unknown; "—" when salary is missing.
  String get salaryPerExperience {
    final salaryValue = double.tryParse(salary);
    if (salaryValue == null || salaryValue <= 0) return '—';
    final years = num.tryParse(experience);
    if (years == null || years <= 0) return 'Fresher';
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    return '${formatter.format(salaryValue / years)} / yr';
  }

  /// Defensively collect the approval levels that have already approved this
  /// onboarding. The backend shape isn't fully known, so we probe several
  /// likely layouts and merge whatever we find:
  ///   1. a list under `approval_logs` / `approvals` / `approval_history` /
  ///      `levels`, where each entry carries a level + an "approved" status;
  ///   2. an `approved_levels` array of numbers;
  ///   3. flat keys like `level1_status` … `level5_status`.
  static List<int> _parseApprovedLevels(Map<String, dynamic> json) {
    final levels = <int>{};

    bool isApproved(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      if (v is num) return v == 1;
      final s = v.toString().trim().toLowerCase();
      return s == 'approved' ||
          s == 'approve' ||
          s == 'approved.' ||
          s == '1' ||
          s == 'true' ||
          s == 'yes';
    }

    int? toLevel(dynamic v) {
      if (v == null) return null;
      final n = int.tryParse(v.toString().replaceAll(RegExp(r'[^0-9]'), ''));
      return (n != null && n > 0) ? n : null;
    }

    // 1. List-of-logs shapes
    for (final key in const [
      'approval_logs',
      'approvals',
      'approval_history',
      'levels',
    ]) {
      final list = json[key];
      if (list is List) {
        for (final entry in list) {
          if (entry is Map) {
            final lvl = toLevel(entry['level'] ?? entry['approval_level']);
            final status = entry['status'] ?? entry['action'] ?? entry['approved'];
            if (lvl != null && isApproved(status)) levels.add(lvl);
          }
        }
      }
    }

    // 2. Plain array of approved level numbers
    final approvedArr = json['approved_levels'];
    if (approvedArr is List) {
      for (final v in approvedArr) {
        final lvl = toLevel(v);
        if (lvl != null) levels.add(lvl);
      }
    }

    // 3. Flat per-level status keys: level1_status / level_1_status
    for (var i = 1; i <= 5; i++) {
      final v = json['level${i}_status'] ?? json['level_${i}_status'];
      if (v != null && isApproved(v)) levels.add(i);
    }

    final sorted = levels.toList()..sort();
    return sorted;
  }
}

class EmployeeOnboardingApprovalScreen extends StatefulWidget {
  const EmployeeOnboardingApprovalScreen({super.key});

  @override
  State<EmployeeOnboardingApprovalScreen> createState() =>
      _EmployeeOnboardingApprovalScreenState();
}

class _EmployeeOnboardingApprovalScreenState
    extends State<EmployeeOnboardingApprovalScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  List<OnboardingRequest> _pendingRequests = [];

  @override
  void initState() {
    super.initState();
    _loadFromApi();
  }

  Future<void> _loadFromApi() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;

      if (token == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Not authenticated. Please log in again.';
        });
        return;
      }

      final response = await ApiService.getOnboardingApprovals(token);

      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        final levelWiseData =
            data['levelWiseData'] as Map<String, dynamic>? ?? {};

        // Flatten all level arrays into a single list
        final List<OnboardingRequest> allRequests = [];
        for (final levelKey in levelWiseData.keys) {
          final levelList = levelWiseData[levelKey];
          // Extract number from key like 'level1' -> '1'
          final levelNumber = levelKey.replaceAll(RegExp(r'[^0-9]'), '');
          if (levelList is List) {
            for (final item in levelList) {
              if (item is Map<String, dynamic>) {
                allRequests.add(
                  OnboardingRequest.fromJson(item, level: levelNumber),
                );
              }
            }
          }
        }

        setState(() {
          _pendingRequests = allRequests;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = response.error ?? 'Failed to load data';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: $e';
      });
    }
  }

  void _handleApproval(OnboardingRequest req, bool isApproved) {
    final action = isApproved ? 'approve' : 'reject';

    // The dialog owns its TextEditingController and returns the typed remark
    // as the pop result. Disposing the controller out here instead — off the
    // showDialog future — would free it BEFORE the exit animation runs
    // (Route.didComplete fires ahead of the pop transition), leaving the still
    // mounted TextField reading a disposed controller.
    showDialog<String>(
      context: context,
      builder: (_) => _ApprovalConfirmDialog(
        employeeName: req.name,
        isApproved: isApproved,
      ),
    ).then((remarks) {
      // null means dismissed/cancelled — do nothing.
      if (remarks == null || !mounted) return;
      _submitApproval(req, action, remarks);
    });
  }

  Future<void> _submitApproval(
    OnboardingRequest req,
    String action, [
    String remarks = '',
  ]) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;

    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not authenticated. Please log in again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final response = await ApiService.postOnboardingApproval(
      token: token,
      action: action,
      empId: req.dbId,
      level: req.level,
      remarks: remarks,
    );

    if (response.isSuccess) {
      setState(() {
        _pendingRequests.removeWhere(
          (r) => r.id == req.id && r.level == req.level,
        );
      });

      // Re-fetch from backend so the UI reflects authoritative state
      // (e.g., employee moved to next approval level).
      _loadFromApi();

      // Drop the in-app notification for *this specific* onboarding so it
      // disappears from the bell list. Uses the `onboarding_id` foreign key
      // on the notification row (planned per
      // docs/laravel-notifications-extend-types.md §4c). No text-fallback
      // here because the broadcast message identifies the submitter, not
      // the onboarded employee — so we'd have nothing reliable to match on.
      // Until the backend ships that column this is a no-op, but
      // `_loadFromApi()` above will sync the screen state regardless.
      final onboardingDbId = int.tryParse(req.dbId);
      if (mounted && onboardingDbId != null) {
        context.read<NotificationProvider>().removeForOnboarding(onboardingDbId);
      }

      // Keep the dashboard badge counts in sync.
      final user = authProvider.currentUser;
      if (user != null) {
        // ignore: use_build_context_synchronously
        context.read<DashboardProvider>().fetchRecentActivity(
              token: token,
              empId: user.employeeId ?? user.id,
              role: user.role,
            );
      }

      final approved = action == 'approve';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                approved ? Icons.check_circle : Icons.cancel,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  approved
                      ? '${req.name} onboarding approved!'
                      : '${req.name} onboarding rejected.',
                ),
              ),
            ],
          ),
          backgroundColor: approved ? AppColors.success : AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.error ?? 'Action failed'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text(
          'Onboarding Approval',
          style: AppTextStyles.headlineMedium.copyWith(
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorState(isDark)
          : _pendingRequests.isEmpty
          ? _buildEmptyState(isDark)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _pendingRequests.length,
              itemBuilder: (context, index) {
                final req = _pendingRequests[index];
                return _buildOnboardingCard(req, isDark, index);
              },
            ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Iconsax.warning_2,
              size: 64,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Something went wrong',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Unknown error',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadFromApi,
            icon: const Icon(Iconsax.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Iconsax.verify,
              size: 64,
              color: AppColors.success,
            ),
          ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 24),
          Text(
            'All Caught Up!',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 8),
          Text(
            'No pending onboarding approvals.',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ).animate().fadeIn(delay: 300.ms),
        ],
      ),
    );
  }

  Widget _buildOnboardingCard(OnboardingRequest req, bool isDark, int index) {
    final borderColor =
        isDark ? const Color(0xFF3C3C3E) : const Color(0xFFE5E7EB);

    return GestureDetector(
      onTap: () => _openDetail(req),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF1F2F3),
              border: Border(
                left: const BorderSide(color: AppColors.warning, width: 5),
                top: BorderSide(color: borderColor),
                right: BorderSide(color: borderColor),
                bottom: BorderSide(color: borderColor),
              ),
            ),
            child: Row(
              children: [
                _buildEmployeeAvatar(req, radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              req.id,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'L${req.level}',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (req.name.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            req.name,
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (req.designation.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            req.designation,
                            style: GoogleFonts.poppins(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textTertiary.withOpacity(0.85),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: (50 * index).ms).slideY(begin: 0.1, end: 0);
  }

  /// Open the full-screen Employee Summary for [req]. Approve/Reject from there
  /// pop back and run the existing confirmation popup + submit flow.
  void _openDetail(OnboardingRequest req) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeOnboardingDetailScreen(
          request: req,
          onAction: (approved) => _handleApproval(req, approved),
        ),
      ),
    );
  }

  Widget _buildEmployeeAvatar(OnboardingRequest req, {double radius = 16}) {
    final initial = req.name.isNotEmpty ? req.name[0].toUpperCase() : '?';
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withOpacity(0.1),
      child: Text(
        initial,
        style: GoogleFonts.poppins(
          fontSize: radius * 0.75,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );

    final url = req.empImageUrl;
    if (url == null || url.isEmpty) return fallback;

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withOpacity(0.1),
      child: ClipOval(
        child: Image.network(
          url,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Text(
              initial,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            );
          },
        ),
      ),
    );
  }

}

/// Approve / Reject confirmation with a free-text remark.
///
/// Stateful so the [TextEditingController] is owned by the dialog and disposed
/// in [State.dispose] — i.e. only once the route is actually gone. The remark
/// travels back to the caller as the pop result, so nothing outside has to
/// touch the controller after the dialog closes.
class _ApprovalConfirmDialog extends StatefulWidget {
  const _ApprovalConfirmDialog({
    required this.employeeName,
    required this.isApproved,
  });

  final String employeeName;
  final bool isApproved;

  @override
  State<_ApprovalConfirmDialog> createState() => _ApprovalConfirmDialogState();
}

class _ApprovalConfirmDialogState extends State<_ApprovalConfirmDialog> {
  final TextEditingController _remarks = TextEditingController();

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isApproved = widget.isApproved;
    final action = isApproved ? 'approve' : 'reject';
    final actionLabel = isApproved ? 'Approve' : 'Reject';
    final accent = isApproved ? AppColors.success : AppColors.error;

    return AlertDialog(
      title: Text('$actionLabel Onboarding'),
      // Scrollable so the field stays reachable once the keyboard is up.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to $action '
              "${widget.employeeName}'s onboarding?",
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _remarks,
              autofocus: !isApproved,
              minLines: 2,
              maxLines: 3,
              maxLength: 250,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(
                labelText: isApproved
                    ? 'Remark (optional)'
                    : 'Reason for rejection (optional)',
                hintText: isApproved
                    ? 'Add a note for the next approver'
                    : 'Why is this being rejected?',
                hintStyle: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
                labelStyle: GoogleFonts.poppins(fontSize: 12.5),
                alignLabelWithHint: true,
                isDense: true,
                counterStyle: GoogleFonts.poppins(fontSize: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: accent, width: 1.4),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _remarks.text.trim()),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
          ),
          child: Text(actionLabel),
        ),
      ],
    );
  }
}
