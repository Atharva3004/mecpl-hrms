import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../services/api_service.dart';
import '../../models/leave_type_model.dart';
import '../../models/leave_balance_model.dart';
import '../../models/leave_application_model.dart';
import '../../models/leave_calculation_model.dart';
import '../../models/user_model.dart';
import '../../models/branch_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/navigation_provider.dart';

enum LeaveDuration { fullDay, firstHalf, secondHalf }

class LeaveScreen extends StatefulWidget {
  final UserModel? targetUser;
  const LeaveScreen({super.key, this.targetUser});

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  List<LeaveBalance> _leaveBalances = [];
  List<LeaveApplication> _leaveHistory = [];
  List<LeaveType> _allLeaveTypes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLeaveTypes();
  }

  Future<void> _fetchLeaveTypes() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      final token = authProvider.token;

      if (token != null && token.isNotEmpty && currentUser != null) {
        final effectiveEmpId = widget.targetUser?.id ?? currentUser.id;

        // Fetch balances
        final balances = await ApiService.getLeaveBalance(
          token: token,
          empId: effectiveEmpId,
        );

        // Fetch all leave types (to ensure all types like C-OFF are available)
        final allTypes = await ApiService.getLeaveTypes(token);

        // Fetch history
        final history = await ApiService.getLeaveHistory(
          token: token,
          empId: widget.targetUser == null ? '' : effectiveEmpId,
        );

        if (mounted) {
          setState(() {
            _leaveBalances = balances;
            _allLeaveTypes = allTypes;
            _leaveHistory = history;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching leave data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openApplyForm() async {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => LeaveApplicationForm(
              leaveTypes: _allLeaveTypes.isNotEmpty
                  ? _allLeaveTypes
                  : _leaveBalances.map((b) => b.leaveType).toList(),
              leaveBalances: _leaveBalances,
              targetUser: widget.targetUser,
            ),
          ),
        )
        .then((success) {
          if (success == true) {
            _fetchLeaveTypes();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.darkBackground
          : const Color(0xFFF8FAFF),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(60, 4, 60, 8),
          child: ElevatedButton.icon(
            onPressed: _openApplyForm,
            icon: const Icon(Iconsax.add, color: Colors.white, size: 18),
            label: Text(
              'Request Leave',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 2,
            ),
          ),
        ),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(context, isDark),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  _buildBalanceSection(isDark),
                  const SizedBox(height: 12),
                  _buildHistoryHeader(isDark),
                ],
              ),
            ),
          ),
          _buildApplicationHistory(isDark),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, bool isDark) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Icon(
          Icons.chevron_left,
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
        onPressed: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          context.read<NavigationProvider>().setIndex(0);
        },
      ),
      title: Text(
        'Leave Management',
        style: AppTextStyles.headlineLarge.copyWith(
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
      ),
      centerTitle: false,
      actions: [
        // IconButton(
        //   icon: Icon(
        //     Iconsax.more,
        //     color: isDark ? Colors.white : AppColors.textPrimary,
        //   ),
        //   onPressed: () {},
        // ),
      ],
    );
  }

  Widget _buildBalanceSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available Quota',
          style: AppTextStyles.titleLarge.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Builder(
                builder: (context) {
                  var displayItems = _allLeaveTypes.isNotEmpty
                      ? _allLeaveTypes.map((type) {
                          try {
                            return _leaveBalances.firstWhere(
                              (b) => b.leaveTypeId == type.id,
                            );
                          } catch (_) {
                            return LeaveBalance(
                              id: 0,
                              empId: 0,
                              leaveTypeId: type.id,
                              year: DateTime.now().year.toString(),
                              balance: 0.0,
                              used: 0.0,
                              encashed: 0.0,
                              createdAt: DateTime.now(),
                              updatedAt: DateTime.now(),
                              leaveType: type,
                            );
                          }
                        }).toList()
                      : _leaveBalances.toList();

                  // Specifically ensure C-OFF is present if still not seen
                  bool hasCoff = displayItems.any(
                    (item) =>
                        item.leaveType.shortName.toUpperCase().contains(
                          'C-OFF',
                        ) ||
                        item.leaveType.leaveName.toUpperCase().contains(
                          'C-OFF',
                        ),
                  );

                  if (!hasCoff) {
                    displayItems.add(
                      LeaveBalance(
                        id: 0,
                        empId: 0,
                        leaveTypeId: 0,
                        year: DateTime.now().year.toString(),
                        balance: 0.0,
                        used: 0.0,
                        encashed: 0.0,
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                        leaveType: LeaveType(
                          id: 0,
                          leaveName: 'Compensatory Off',
                          shortName: 'C-OFF',
                          gender: 'All',
                          maxLeave: 0,
                          presentDays: 0,
                          completeHours: 0,
                          minService: 0,
                          leaveCaFw: 'No',
                          leaveEncashment: 'No',
                          aId: 0,
                          delete: 0,
                        ),
                      ),
                    );
                  }

                  // Hide Maternity Leave (ML) if balance is 0
                  // Only show ML when it is actually allocated to the employee
                  displayItems.removeWhere((item) {
                    final name = item.leaveType.leaveName.toUpperCase();
                    final short = item.leaveType.shortName.toUpperCase();
                    final isMaternity = name.contains('MATERNITY') || short == 'ML';
                    return isMaternity && item.balance <= 0;
                  });

                  // Build rows of 3 chips each
                  final rows = <Widget>[];
                  for (int i = 0; i < displayItems.length; i += 3) {
                    final rowChildren = <Widget>[];
                    for (int j = i; j < i + 3; j++) {
                      if (j < displayItems.length) {
                        if (rowChildren.isNotEmpty) {
                          rowChildren.add(const SizedBox(width: 4));
                        }
                        rowChildren.add(
                          Expanded(
                            child: _buildBalanceChip(
                              displayItems[j],
                              j,
                              isDark,
                            ),
                          ),
                        );
                      } else {
                        if (rowChildren.isNotEmpty) {
                          rowChildren.add(const SizedBox(width: 8));
                        }
                        rowChildren.add(const Expanded(child: SizedBox()));
                      }
                    }
                    rows.add(Row(children: rowChildren));
                    if (i + 3 < displayItems.length) {
                      rows.add(const SizedBox(height: 8));
                    }
                  }
                  return Column(children: rows);
                },
              ),
      ],
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildBalanceChip(LeaveBalance balance, int index, bool isDark) {
    final leave = balance.leaveType;
    final available = balance.balance;

    // Color assignment based on leave type
    Color color;
    final nameUpper = leave.leaveName.toUpperCase();
    if (nameUpper.contains('PRIVILEGE') ||
        leave.shortName.toUpperCase().contains('PL')) {
      color = const Color(0xFF6366F1); // Indigo/Purple
    } else if (nameUpper.contains('OFF') || nameUpper.contains('C-OFF')) {
      color = const Color(0xFFEF4444); // Red
    } else {
      final colors = [
        const Color(0xFF6366F1),
        const Color(0xFFEF4444),
        const Color(0xFF10B981),
        const Color(0xFFF59E0B),
      ];
      color = colors[index % colors.length];
    }

    final balanceText = available.toStringAsFixed(
      available.truncateToDouble() == available ? 0 : 1,
    );

    return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurface.withOpacity(0.7)
                : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : color.withOpacity(0.2),
            ),
          ),
          child: Row(
            children: [
              // Colored dot indicator
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              // Leave type short name
              Expanded(
                child: Text(
                  leave.shortName,
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white70 : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              // Balance count
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isDark
                      ? color.withOpacity(0.3)
                      : color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  balanceText,
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white : AppColors.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: (200 + index * 80).ms)
        .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1));
  }

  Widget _buildHistoryHeader(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Leave Requests',
          style: AppTextStyles.titleLarge.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        // TextButton(
        //   onPressed: () {},
        //   child: Text(
        //     'View Detailed',
        //     style: GoogleFonts.poppins(
        //       color: AppColors.primary,
        //       fontWeight: FontWeight.w600,
        //       fontSize: 13,
        //     ),
        //   ),
        // ),
      ],
    ).animate().fadeIn(delay: 400.ms);
  }

  Widget _buildApplicationHistory(bool isDark) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: _leaveHistory.isEmpty && !_isLoading
          ? SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(
                    'No leave requests found',
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
                ),
              ),
            )
          : SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.border,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Table header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: const BoxDecoration(
                        color: Color.fromARGB(255, 92, 151, 244),
                      ),
                      child: Row(
                        children: [
                          _tableHeader('Type', 60, isDark),
                          _tableHeader('Dates', 100, isDark, flex: true),
                          _tableHeader('Days', 40, isDark),
                          _tableHeader('Status', 70, isDark),
                        ],
                      ),
                    ),
                    // Table rows
                    ...List.generate(_leaveHistory.length, (index) {
                      return _buildHistoryRow(
                        _leaveHistory[index],
                        index,
                        isDark,
                      );
                    }),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms),
            ),
    );
  }

  Widget _tableHeader(
    String title,
    double width,
    bool isDark, {
    bool flex = false,
  }) {
    final widget = Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: 0.5,
      ),
    );
    if (flex) {
      return Expanded(child: widget);
    }
    return SizedBox(width: width, child: widget);
  }

  Widget _buildHistoryRow(LeaveApplication app, int index, bool isDark) {
    Color statusColor;
    switch (app.status.toLowerCase()) {
      case 'approved':
        statusColor = AppColors.success;
        break;
      case 'rejected':
        statusColor = AppColors.error;
        break;
      default:
        statusColor = AppColors.warning;
    }

    final isEven = index % 2 == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isEven
            ? Colors.transparent
            : (isDark
                  ? Colors.white.withOpacity(0.02)
                  : const Color(0xFFFAFBFD)),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkBorder.withOpacity(0.3)
                : AppColors.border.withOpacity(0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Type
          SizedBox(
            width: 60,
            child: Text(
              app.leaveType.shortName,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Dates
          Expanded(
            child: Text(
              '${DateFormat('dd MMM').format(app.fromDate)} - ${DateFormat('dd MMM').format(app.toDate)}',
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: isDark ? Colors.white70 : AppColors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Days
          SizedBox(
            width: 40,
            child: Text(
              app.netLeaveDays.formatDecimal(),
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          // Status
          SizedBox(
            width: 70,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                app.status,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LeaveApplicationForm extends StatefulWidget {
  final List<LeaveType> leaveTypes;
  final List<LeaveBalance> leaveBalances;
  final UserModel? targetUser;
  final bool isApplyingForOther;
  final List<BranchModel>? preloadedBranches;
  final List<UserModel>? preloadedEmployees;

  const LeaveApplicationForm({
    super.key,
    required this.leaveTypes,
    this.leaveBalances = const [],
    this.targetUser,
    this.isApplyingForOther = false,
    this.preloadedBranches,
    this.preloadedEmployees,
  });

  @override
  State<LeaveApplicationForm> createState() => _LeaveApplicationFormState();
}

class _LeaveApplicationFormState extends State<LeaveApplicationForm> {
  final _formKey = GlobalKey<FormState>();
  LeaveType? _selectedLeaveType;
  String _leaveCategory = 'Paid';
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _reasonController = TextEditingController();

  LeaveDuration _leaveDuration = LeaveDuration.fullDay;

  LeaveCalculationResponse? _calculationResult;
  bool _isCalculating = false;
  String? _calculationError;

  // For 'Other' employee selection
  bool _isLoadingEmployees = false;
  List<UserModel> _allEmployees = [];
  List<UserModel> _filteredEmployees = [];
  List<BranchModel> _allBranches = [];
  BranchModel? _selectedBranch;
  UserModel? _selectedEmployee;
  final TextEditingController _searchController = TextEditingController();
  List<LeaveType> _dynamicLeaveTypes = [];
  List<LeaveBalance> _dynamicLeaveBalances = [];
  bool _isLoadingLeaveTypes = false;

  @override
  void initState() {
    super.initState();
    _selectedEmployee = widget.targetUser;
    _dynamicLeaveTypes = widget.leaveTypes;

    if (_dynamicLeaveTypes.isNotEmpty) {
      _selectedLeaveType = _dynamicLeaveTypes.first;
    }

    if (widget.isApplyingForOther) {
      // Set branches immediately if preloaded, so dropdown appears instantly
      if (widget.preloadedBranches != null &&
          widget.preloadedBranches!.isNotEmpty) {
        _allBranches = widget.preloadedBranches!;
        // Auto-select branch if only one (e.g., onsite admin filtered to their branch)
        if (_allBranches.length == 1) {
          _selectedBranch = _allBranches.first;
        }
      }
      // Set employees immediately if preloaded
      if (widget.preloadedEmployees != null &&
          widget.preloadedEmployees!.isNotEmpty) {
        _allEmployees = widget.preloadedEmployees!;
        _filteredEmployees = widget.preloadedEmployees!;
      }
      _loadEmployees();
    }
    // Initialize with default empty result to show the card immediately (as per user request)
    _calculationResult = LeaveCalculationResponse(
      success: true,
      totalDays: 0.0,
      paidHolidays: 0.0,
      weeklyOffs: 0.0,
      netLeaveDays: 0.0,
      balanceAvailable: 0.0,
      isExceeded: false,
      paidDays: 0.0,
      unpaidDays: 0.0,
      holidayList: [],
      weeklyOffDates: [],
      allDatesOff: false,
      forceUnpaid: false,
      hasDuplicate: false,
      salaryProcessed: false,
      compulsoryHolidays: [],
      optionalHolidays: [],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    // If both branches and employees are already preloaded, skip all fetching
    if (widget.preloadedBranches != null &&
        widget.preloadedBranches!.isNotEmpty &&
        widget.preloadedEmployees != null &&
        widget.preloadedEmployees!.isNotEmpty) {
      return;
    }
    setState(() => _isLoadingEmployees = true);
    try {
      final auth = context.read<AuthProvider>();
      final token = auth.token;
      if (token == null) return;

      final employeesResponse = await ApiService.getEmployees(token);
      // Use preloaded branches if available, otherwise fetch
      final branches =
          widget.preloadedBranches ?? await ApiService.getBranches(token);

      if (employeesResponse.isSuccess && employeesResponse.data != null) {
        final employees = ApiService.parseEmployeesFromResponse(
          employeesResponse.data!,
        );

        if (mounted) {
          setState(() {
            _allEmployees = employees;
            _allBranches = branches;
            _filteredEmployees = employees;
            _isLoadingEmployees = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _allBranches = branches;
            _isLoadingEmployees = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading employees: $e');
      if (mounted) setState(() => _isLoadingEmployees = false);
    }
  }

  Future<void> _onBranchChanged(BranchModel? branch) async {
    setState(() {
      _selectedBranch = branch;
      _selectedEmployee = null;
      _dynamicLeaveTypes = [];
      _selectedLeaveType = null;
      _searchController.clear();
      _calculationResult = null;
      _isLoadingEmployees = true; // Use loading state for branch-specific fetch
    });

    try {
      if (branch == null) {
        setState(() {
          _filteredEmployees = _allEmployees;
          _isLoadingEmployees = false;
        });
      } else {
        final auth = context.read<AuthProvider>();
        final token = auth.token;
        if (token != null) {
          final employees = await ApiService.getEmployeesByBranch(
            token: token,
            branchId: branch.id,
          );
          if (mounted) {
            setState(() {
              _filteredEmployees = employees;
              _isLoadingEmployees = false;
            });
          }
        } else {
          if (mounted) setState(() => _isLoadingEmployees = false);
        }
      }
    } catch (e) {
      debugPrint('Error fetching employees for branch: $e');
      if (mounted) setState(() => _isLoadingEmployees = false);
    }
  }

  void _onEmployeeSelected(UserModel employee) {
    setState(() {
      _selectedEmployee = employee;
      _searchController.text = employee.fullName;
      _calculationResult = null;
    });
    _fetchLeaveTypesForEmployee(employee);
  }

  Future<void> _fetchLeaveTypesForEmployee(UserModel employee) async {
    setState(() {
      _isLoadingLeaveTypes = true;
      _dynamicLeaveBalances = [];
    });
    try {
      final auth = context.read<AuthProvider>();
      final token = auth.token;
      if (token == null) return;

      final results = await Future.wait([
        ApiService.getLeaveTypes(token),
        ApiService.getLeaveBalance(token: token, empId: employee.id),
      ]);
      final types = results[0] as List<LeaveType>;
      final balances = results[1] as List<LeaveBalance>;

      if (mounted) {
        setState(() {
          _dynamicLeaveTypes = types;
          _dynamicLeaveBalances = balances;
          if (types.isNotEmpty) _selectedLeaveType = types.first;
          _isLoadingLeaveTypes = false;
        });
        if (_startDate != null && _endDate != null) {
          _calculateDays();
        }
      }
    } catch (e) {
      debugPrint('Error fetching leave types/balances: $e');
      if (mounted) setState(() => _isLoadingLeaveTypes = false);
    }
  }

  bool _canCalculate() {
    if (_selectedLeaveType == null) return false;
    if (_startDate == null || _endDate == null) return false;
    if (_endDate!.isBefore(_startDate!)) return false;
    if (widget.isApplyingForOther && _selectedEmployee == null) return false;
    return true;
  }

  Future<void> _calculateDays() async {
    debugPrint("🔄 calculateDays triggered");

    if (!_canCalculate()) return;

    setState(() {
      _isCalculating = true;
      _calculationError = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      final token = authProvider.token;

      if (token == null || token.isEmpty) {
        throw Exception("Auth token missing");
      }

      final branchId =
          (_selectedEmployee?.branchId ?? currentUser?.branchId ?? 1)
              .toString();

      final halfDayFlag = _leaveDuration == LeaveDuration.fullDay
          ? "Full Day"
          : _leaveDuration == LeaveDuration.firstHalf
          ? "First Half"
          : "Second Half";

      final result = await ApiService.calculateLeaveDays(
        token: token,
        fromDate: DateFormat('yyyy-MM-dd').format(_startDate!),
        toDate: DateFormat('yyyy-MM-dd').format(_endDate!),
        halfDay: halfDayFlag,
        leaveTypeId: _selectedLeaveType!.id.toString(),
        branchId: branchId,
        employeeId: _selectedEmployee?.id
            .toString(), // Pass selected employee's ID
      );
      debugPrint("📦 Raw calculateLeaveDays result: $result");

      if (mounted && result != null) {
        // Check client-side balance for the selected leave type.
        // The API sometimes returns isExceeded:true even when the local
        // balance shows enough days — use local balance as the source of truth
        // when available. In the apply-for-other flow the balances are
        // fetched per-selected-employee into _dynamicLeaveBalances.
        final balancesSource = _dynamicLeaveBalances.isNotEmpty
            ? _dynamicLeaveBalances
            : widget.leaveBalances;
        final clientBal = balancesSource
            .where((b) => b.leaveTypeId == _selectedLeaveType?.id)
            .firstOrNull;

        final bool isActuallyExceeded;
        if (clientBal != null) {
          // Client has balance data — trust it over the API flag
          isActuallyExceeded = clientBal.balance < result.netLeaveDays;
        } else {
          // No local balance data — fall back to API flag
          isActuallyExceeded = result.isExceeded;
        }

        setState(() {
          _calculationResult = result;
          if (isActuallyExceeded || result.forceUnpaid) {
            _leaveCategory = 'Unpaid';
          } else {
            _leaveCategory = 'Paid';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _calculationError = "Unable to calculate leave days: $e";
          _isCalculating = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isCalculating = false);
      }
    }
  }

  // Future<void> _calculateDays() async {
  //   if (_startDate == null || _endDate == null || _selectedLeaveType == null) {
  //     return;
  //   }

  //   setState(() {
  //     _isCalculating = true;
  //     _calculationResult = null;
  //     _calculationError = null;
  //   });

  //   try {
  //     final prefs = await SharedPreferences.getInstance();
  //     final token = prefs.getString('auth_token');

  //     // Need branch_id, usually from profile.
  //     // For now, passing empty string as per snippet or maybe we can fetch user profile?
  //     // The snippet used 'branch_id': ''

  //     final halfDayStr = _leaveDuration == LeaveDuration.fullDay
  //         ? 'Full Day'
  //         : _leaveDuration == LeaveDuration.firstHalf
  //         ? 'First Half'
  //         : 'Second Half';

  //     if (token != null) {
  //       final result = await ApiService.calculateLeaveDays(
  //         token: token,
  //         fromDate: DateFormat('dd-MM-yyyy').format(_startDate!),
  //         toDate: DateFormat('dd-MM-yyyy').format(_endDate!),
  //         halfDay: halfDayStr,
  //         leaveTypeId: _selectedLeaveType!.id.toString(),
  //         branchId: '', // As per user snippet example
  //       );

  //       if (mounted) {
  //         setState(() {
  //           _calculationResult = result;
  //           _isCalculating = false;
  //         });
  //       }
  //     } else {
  //       if (mounted) setState(() => _isCalculating = false);
  //     }
  //   } catch (e) {
  //     if (mounted) {

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        backgroundColor: isDark
            ? AppColors.darkBackground
            : AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Apply for Leave',
          style: AppTextStyles.headlineLarge.copyWith(
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBackground : Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // const SizedBox(height: 12),
              /*
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              */
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row(
                        //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        //   children: [
                        //     Text(
                        //       'Apply for Leave',
                        // ...
                        //     ),
                        //     IconButton(
                        //       onPressed: () => Navigator.pop(context),
                        //       icon: const Icon(Iconsax.close_circle),
                        //       color: isDark ? Colors.white70 : Colors.black45,
                        //     ),
                        //   ],
                        // ),
                        if (widget.targetUser != null &&
                            !widget.isApplyingForOther) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Iconsax.user,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Applying for: ${widget.targetUser!.fullName}",
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        if (widget.isApplyingForOther) ...[
                          _buildSelectionSection(isDark),
                        ],
                        const SizedBox(height: 16),
                        // Text(
                        //   'Fill in your request details below',
                        //   style: GoogleFonts.poppins(
                        //     fontSize: 13,
                        //     color: AppColors.textTertiary,

                        //   ),
                        // ),
                        // const SizedBox(height: 16),
                        _buildLabel('Leave Type'),
                        _buildDropdown(isDark),
                        _buildBalanceBadge(),

                        const SizedBox(height: 20),
                        // User snippet didn't emphasize category selection, but I'll keep UI if user wants
                        // But calculations are based on type.
                        _buildLabel('Leave Category'),
                        Wrap(
                          spacing: 24,
                          runSpacing: 8,
                          children: [
                            _buildRadioOption('Paid', isDark),
                            _buildRadioOption('Unpaid', isDark),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: _buildLabel('From Date')),
                            const SizedBox(width: 16),
                            Expanded(child: _buildLabel('To Date')),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDatePicker(
                                context,
                                'From Date',
                                true,
                                isDark,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildDatePicker(
                                context,
                                'To Date',
                                false,
                                isDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        _buildLabel('Leave Duration'),

                        Builder(
                          builder: (context) {
                            final daysCount =
                                (_startDate != null && _endDate != null)
                                ? _endDate!.difference(_startDate!).inDays + 1
                                : 0;
                            final isTooLong = daysCount > 2;

                            // Auto-reset to full day if more than 2 days are selected
                            if (isTooLong &&
                                _leaveDuration != LeaveDuration.fullDay) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(() {
                                    _leaveDuration = LeaveDuration.fullDay;
                                  });
                                  _calculateDays();
                                }
                              });
                            }

                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildLeaveDurationOption(
                                    'Full Day',
                                    LeaveDuration.fullDay,
                                    isDark,
                                  ),
                                  const SizedBox(width: 16),
                                  _buildLeaveDurationOption(
                                    'First Half',
                                    LeaveDuration.firstHalf,
                                    isDark,
                                    isEnabled: !isTooLong,
                                  ),
                                  const SizedBox(width: 16),
                                  _buildLeaveDurationOption(
                                    'Second Half',
                                    LeaveDuration.secondHalf,
                                    isDark,
                                    isEnabled: !isTooLong,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        if (_isCalculating)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),

                        if (_calculationResult != null)
                          _buildCalculationResult(isDark),

                        if (_calculationError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              _calculationError!,
                              style: TextStyle(color: AppColors.error),
                            ),
                          ),

                        const SizedBox(height: 8),
                        _buildLabel('Reason for Leave'),
                        TextFormField(
                          controller: _reasonController,
                          maxLines: 4,
                          style: GoogleFonts.poppins(fontSize: 14),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please provide a reason for leave';
                            }
                            if (value.trim().length < 10) {
                              return 'Reason should be at least 10 characters';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'Describe your reason here...',
                            hintStyle: GoogleFonts.poppins(
                              color: AppColors.textTertiary,
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? AppColors.darkSurface
                                : const Color(0xFFF6F7FB),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 2,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: const BorderSide(
                                color: AppColors.error,
                                width: 1,
                              ),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: const BorderSide(
                                color: AppColors.error,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isCalculating
                                  ? null
                                  : () async {
                                      if (_formKey.currentState!.validate()) {
                                        if (_startDate == null ||
                                            _endDate == null) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Please select both From and To dates',
                                                style: GoogleFonts.poppins(),
                                              ),
                                              backgroundColor: AppColors.error,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }

                                        if (_endDate!.isBefore(_startDate!)) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'To Date cannot be before From Date',
                                                style: GoogleFonts.poppins(),
                                              ),
                                              backgroundColor: AppColors.error,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }

                                        if (_calculationResult != null &&
                                            _calculationResult!.hasDuplicate) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                _calculationResult!
                                                        .duplicateMessage ??
                                                    'Duplicate leave request',
                                                style: GoogleFonts.poppins(),
                                              ),
                                              backgroundColor: AppColors.error,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }

                                        // If all validations pass
                                        setState(() => _isCalculating = true);

                                        try {
                                          final authProvider =
                                              Provider.of<AuthProvider>(
                                                context,
                                                listen: false,
                                              );
                                          final currentUser =
                                              authProvider.currentUser;
                                          final token = authProvider.token;

                                          if (token == null) {
                                            throw Exception(
                                              "Auth token missing",
                                            );
                                          }

                                          final branchId =
                                              (_selectedEmployee?.branchId ??
                                                      currentUser?.branchId ??
                                                      1)
                                                  .toString();

                                          final halfDayValue =
                                              _leaveDuration ==
                                                  LeaveDuration.fullDay
                                              ? "Full Day"
                                              : _leaveDuration ==
                                                    LeaveDuration.firstHalf
                                              ? "First Half"
                                              : "Second Half";

                                          final response =
                                              widget.isApplyingForOther &&
                                                  _selectedEmployee != null
                                              ? await ApiService.storeEmployeeLeave(
                                                  token: token,
                                                  empId: _selectedEmployee!.id
                                                      .toString(),
                                                  fromDate: DateFormat(
                                                    'yyyy-MM-dd',
                                                  ).format(_startDate!),
                                                  toDate: DateFormat(
                                                    'yyyy-MM-dd',
                                                  ).format(_endDate!),
                                                  leaveType: _selectedLeaveType!
                                                      .id
                                                      .toString(),
                                                  category: _leaveCategory,
                                                  halfDay: halfDayValue,
                                                  reason:
                                                      _reasonController.text,
                                                )
                                              : await ApiService.applyLeave(
                                                  token: token,
                                                  leaveTypeId:
                                                      _selectedLeaveType!.id
                                                          .toString(),
                                                  startDate: DateFormat(
                                                    'yyyy-MM-dd',
                                                  ).format(_startDate!),
                                                  endDate: DateFormat(
                                                    'yyyy-MM-dd',
                                                  ).format(_endDate!),
                                                  reason:
                                                      _reasonController.text,
                                                  leaveCategory: _leaveCategory,
                                                  halfDayValue: halfDayValue,
                                                  branchId: branchId,
                                                  employeeId:
                                                      _selectedEmployee?.id ??
                                                      currentUser?.id,
                                                );

                                          if (!mounted) return;

                                          if (response.isSuccess) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Leave request submitted successfully!',
                                                  style: GoogleFonts.poppins(),
                                                ),
                                                backgroundColor:
                                                    AppColors.success,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                            Navigator.of(context).pop(true);
                                          } else {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  response.error ??
                                                      'Failed to submit leave request',
                                                  style: GoogleFonts.poppins(),
                                                ),
                                                backgroundColor:
                                                    AppColors.error,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Error submitting request: $e',
                                                  style: GoogleFonts.poppins(),
                                                ),
                                                backgroundColor:
                                                    AppColors.error,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(
                                              () => _isCalculating = false,
                                            );
                                          }
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                disabledBackgroundColor: Colors.grey.shade400,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 4,
                              ),
                              child: Text(
                                'Submit Request',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildBalanceBadge() {
    if (_selectedLeaveType == null) return const SizedBox.shrink();
    if (widget.isApplyingForOther) return const SizedBox.shrink();

    final bal = widget.leaveBalances
        .where((b) => b.leaveTypeId == _selectedLeaveType!.id)
        .firstOrNull;

    if (bal == null) return const SizedBox.shrink();

    final available = bal.balance;
    final used = bal.used;
    final isEnough = available > 0;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isEnough ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isEnough
              ? const Color(0xFF4CAF50).withValues(alpha: 0.3)
              : const Color(0xFFE53935).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isEnough ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            size: 16,
            color: isEnough ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
          ),
          const SizedBox(width: 8),
          Text(
            isEnough
                ? 'Available balance: ${available % 1 == 0 ? available.toInt() : available} days'
                : 'No balance available — will be Unpaid (LWP)',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isEnough ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
            ),
          ),
          if (isEnough) ...[
            const Spacer(),
            Text(
              'Used: ${used % 1 == 0 ? used.toInt() : used}',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdown(bool isDark) {
    if (_isLoadingLeaveTypes) {
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : const Color(0xFFF6F7FB),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_dynamicLeaveTypes.isEmpty && !widget.isApplyingForOther) {
      return Text(
        "No leave types available",
        style: TextStyle(color: AppColors.textTertiary),
      );
    }

    if (_dynamicLeaveTypes.isEmpty && widget.isApplyingForOther) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : const Color(0xFFF6F7FB),
          borderRadius: BorderRadius.circular(20),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<LeaveType>(
            value: null,
            isExpanded: true,
            dropdownColor: isDark ? AppColors.darkSurface : Colors.white,
            hint: Text(
              _selectedEmployee == null
                  ? "Select Employee First"
                  : "No leave types found",
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            items: const [],
            onChanged: null,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<LeaveType>(
          value: _selectedLeaveType,
          isExpanded: true,
          dropdownColor: isDark ? AppColors.darkSurface : Colors.white,
          items: _dynamicLeaveTypes.map((LeaveType type) {
            final balancesSource = _dynamicLeaveBalances.isNotEmpty
                ? _dynamicLeaveBalances
                : widget.leaveBalances;
            final bal = balancesSource
                .where((b) => b.leaveTypeId == type.id)
                .firstOrNull;
            final availableBalance = bal?.balance ?? 0.0;
            return DropdownMenuItem<LeaveType>(
              value: type,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      type.leaveName,
                      style: GoogleFonts.poppins(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (bal != null)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: availableBalance > 0
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${availableBalance % 1 == 0 ? availableBalance.toInt() : availableBalance} left',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: availableBalance > 0
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFC62828),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
          onChanged: (LeaveType? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedLeaveType = newValue;
                _leaveCategory = 'Paid';
                _calculationResult = null;
              });
              _calculateDays();
            }
          },
        ),
      ),
    );
  }

  /// Returns true if the leave balance is truly exceeded,
  /// using client-side balance as source of truth when available.
  bool _isBalanceExceeded(LeaveCalculationResponse res) {
    final balancesSource = _dynamicLeaveBalances.isNotEmpty
        ? _dynamicLeaveBalances
        : widget.leaveBalances;
    final clientBal = balancesSource
        .where((b) => b.leaveTypeId == _selectedLeaveType?.id)
        .firstOrNull;
    if (clientBal != null) {
      return clientBal.balance < res.netLeaveDays;
    }
    return res.isExceeded;
  }

  Widget _buildCalculationResult(bool isDark) {
    final res = _calculationResult!;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.textTertiary,
        title: Row(
          children: [
            Icon(Iconsax.calendar_tick, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Summary',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        children: [
          const SizedBox(height: 12),
          // Alert Box (if needed)
          if (_isBalanceExceeded(res) ||
              res.unpaidDays > 0 ||
              res.hasDuplicate ||
              res.salaryProcessed ||
              res.allDatesOff)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Iconsax.warning_2,
                    color: Color(0xFFD97706),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      res.allDatesOff
                          ? "Invalid dates selection"
                          : res.hasDuplicate
                          ? (res.duplicateMessage ?? "Duplicate dates!")
                          : res.salaryProcessed
                          ? (res.salaryMessage ?? "Salary already processed!")
                          : _isBalanceExceeded(res)
                          ? "Balance Exceeded!"
                          : "${res.unpaidDays.formatDecimal()} days Unpaid (LWP)",
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF92400E),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // The "No Card" Trendy Strip
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : AppColors.primary.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTrendyStat(
                    "Total",
                    res.totalDays.formatDecimal(),
                    const Color(0xFF6366F1), // Indigo
                    Iconsax.calendar,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey.withOpacity(0.2),
                ),
                Expanded(
                  child: _buildTrendyStat(
                    "Holidays",
                    res.paidHolidays.formatDecimal(),
                    const Color(0xFFF59E0B), // Amber
                    Iconsax.star,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey.withOpacity(0.2),
                ),
                Expanded(
                  child: _buildTrendyStat(
                    "Offs",
                    res.weeklyOffs.formatDecimal(),
                    const Color(0xFF10B981), // Emerald
                    Iconsax.moon,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey.withOpacity(0.2),
                ),
                Expanded(
                  flex: 1,
                  child: _buildTrendyStat(
                    "Net",
                    res.netLeaveDays.formatDecimal(),
                    const Color(0xFFEF4444), // Red
                    Iconsax.tick_circle,
                    isNet: true,
                    subText: res.unpaidDays > 0
                        ? "(${res.unpaidDays.formatDecimal()} LWP)"
                        : "Paid",
                  ),
                ),
              ],
            ),
          ),
          // Breakdown Toggle (Minimal)
          if (res.holidayList.isNotEmpty || res.weeklyOffDates.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: false,
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    "View Breakdown",
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.05)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          if (res.holidayList.isNotEmpty) ...[
                            _buildBreakdownRow(
                              "Holidays",
                              const Color(0xFFF59E0B),
                            ),
                            ...res.holidayList.map(
                              (h) => _buildBreakdownItem(
                                DateFormat(
                                  'd MMM',
                                ).format(DateTime.parse(h['date'])),
                                h['name'] ?? '',
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (res.weeklyOffDates.isNotEmpty) ...[
                            _buildBreakdownRow(
                              "Weekly Offs",
                              const Color(0xFF6366F1),
                            ),
                            ...res.weeklyOffDates.map(
                              (d) => _buildBreakdownItem(
                                DateFormat('d MMM').format(DateTime.parse(d)),
                                DateFormat('EEEE').format(DateTime.parse(d)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildTrendyStat(
    String label,
    String value,
    Color color,
    IconData icon, {
    bool isNet = false,
    String? subText,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
          ),
        ),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 9,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        if (subText != null)
          Text(
            subText,
            style: GoogleFonts.poppins(
              fontSize: 8,
              color: color.withOpacity(0.8),
            ),
          ),
      ],
    );
  }

  Widget _buildBreakdownRow(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownItem(String date, String name) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(date, style: GoogleFonts.poppins(fontSize: 10)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker(
    BuildContext context,
    String label,
    bool isStart,
    bool isDark,
  ) {
    final date = isStart ? _startDate : _endDate;
    final text = date == null ? label : DateFormat('dd MMM yyyy').format(date);

    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          currentDate: DateTime.now(),
          firstDate: AppConstants.appStartDate,
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) {
          setState(() {
            if (isStart) {
              _startDate = picked;
            } else {
              _endDate = picked;
            }

            // Auto-set the other date if not set or invalid
            if (isStart &&
                (_endDate == null || _endDate!.isBefore(_startDate!))) {
              _endDate = _startDate;
            }

            _leaveCategory = 'Paid';
          });
          _calculateDays();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : const Color(0xFFF6F7FB),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Iconsax.calendar, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: date == null
                      ? AppColors.textTertiary
                      : (isDark ? Colors.white : Colors.black),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioOption(String value, bool isDark) {
    final isSelected = _leaveCategory == value;
    return InkWell(
      onTap: () {
        setState(() {
          _leaveCategory = value;
          _calculationResult = null;
        });
        _calculateDays();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppColors.primary : Colors.grey,
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: isSelected
                ? Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: isDark ? Colors.white : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Branch Field
        _buildLabel('Branch'),
        if (_allBranches.isEmpty && _isLoadingEmployees)
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : const Color(0xFFF6F7FB),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : const Color(0xFFF6F7FB),
              borderRadius: BorderRadius.circular(20),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<BranchModel?>(
                value: _selectedBranch,
                isExpanded: true,
                dropdownColor: isDark ? AppColors.darkSurface : Colors.white,
                hint: Text(
                  'Select Branch',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                items: [
                  DropdownMenuItem<BranchModel?>(
                    value: null,
                    child: Text(
                      'All Branches',
                      style: GoogleFonts.poppins(fontSize: 14),
                    ),
                  ),
                  ..._allBranches.map(
                    (branch) => DropdownMenuItem<BranchModel?>(
                      value: branch,
                      child: Text(
                        branch.branchName,
                        style: GoogleFonts.poppins(fontSize: 14),
                      ),
                    ),
                  ),
                ],
                onChanged: _isLoadingEmployees ? null : _onBranchChanged,
              ),
            ),
          ),
        const SizedBox(height: 20),

        // Employee Field
        _buildLabel('Employee'),
        if (_allBranches.isNotEmpty && _isLoadingEmployees)
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : const Color(0xFFF6F7FB),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          _buildEmployeeSearchField(isDark),
      ],
    );
  }

  Widget _buildEmployeeSearchField(bool isDark) {
    return Autocomplete<UserModel>(
      optionsBuilder: (TextEditingValue textValue) {
        if (textValue.text.isEmpty) {
          return _filteredEmployees;
        }
        final query = textValue.text.toLowerCase();
        return _filteredEmployees.where((e) {
          final name = e.fullName.toLowerCase();
          final code = (e.employeeId ?? '').toLowerCase();
          return name.contains(query) || code.contains(query);
        });
      },
      displayStringForOption: (UserModel e) =>
          '${e.fullName} (#${e.employeeId ?? e.id})',
      onSelected: _onEmployeeSelected,
      optionsMaxHeight: 250,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        // Only override to set the text logic or style, but we'll use a listener to keep text
        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Search by name or ID...',
            hintStyle: GoogleFonts.poppins(
              fontSize: 14,
              color: isDark ? Colors.white38 : AppColors.textTertiary,
            ),
            prefixIcon: Icon(
              Iconsax.search_normal,
              size: 18,
              color: isDark ? Colors.white38 : Colors.grey,
            ),
            filled: true,
            fillColor: isDark ? AppColors.darkSurface : const Color(0xFFF6F7FB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: isDark ? AppColors.darkSurface : Colors.white,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 250,
                maxWidth: MediaQuery.of(context).size.width - 64,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final employee = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(employee),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: isDark
                                ? AppColors.darkBorder
                                : Colors.grey.shade100,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.primary.withOpacity(0.1),
                            child: Text(
                              employee.initials,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  employee.fullName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  '#${employee.employeeId ?? employee.id} • ${employee.designation ?? 'N/A'}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeaveDurationOption(
    String label,
    LeaveDuration value,
    bool isDark, {
    bool isEnabled = true,
  }) {
    final selected = _leaveDuration == value;

    return InkWell(
      onTap: isEnabled
          ? () {
              setState(() => _leaveDuration = value);
              _calculateDays();
            }
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.4,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : (isDark ? Colors.white24 : Colors.grey.shade400),
                  width: 2,
                ),
              ),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : Colors.transparent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? (isDark ? Colors.white : AppColors.textPrimary)
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension DoubleExtension on double {
  String formatDecimal() {
    try {
      if (truncateToDouble() == this) {
        return toInt().toString();
      }
      return toStringAsFixed(1);
    } catch (e) {
      return toString();
    }
  }
}
