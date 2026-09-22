import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/user_model.dart';
import '../../models/role_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../profile/profile_screen.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import 'package:provider/provider.dart';
import '../../widgets/common/custom_loader.dart';
import '../leave/leave_screen.dart';

/// Session-level cache for the full /employees API response. The endpoint
/// can return hundreds of users, so re-fetching every time the user enters
/// the Employee Details screen makes it feel slow. We keep the result here
/// across navigations within the same app session; entries past the TTL are
/// ignored so the screen never shows truly stale data.
class _EmployeesCache {
  static List<UserModel>? _data;
  static DateTime? _fetchedAt;
  static const Duration _ttl = Duration(minutes: 5);

  static List<UserModel>? get() {
    if (_data == null || _fetchedAt == null) return null;
    if (DateTime.now().difference(_fetchedAt!) > _ttl) return null;
    return _data;
  }

  static void set(List<UserModel> employees) {
    _data = employees;
    _fetchedAt = DateTime.now();
  }
}

class EmployeeDetailsScreen extends StatefulWidget {
  final bool showApplyLeave;
  const EmployeeDetailsScreen({super.key, this.showApplyLeave = false});

  @override
  State<EmployeeDetailsScreen> createState() => _EmployeeDetailsScreenState();
}

class _EmployeeDetailsScreenState extends State<EmployeeDetailsScreen> {
  // Raw API result — never mutated except on a fresh fetch. The role
  // filtering reads from this so subsequent refreshes don't shrink the
  // list each time (the earlier code did `_allEmployees = filteredList`
  // on every call, which was a bug when refresh was added).
  List<UserModel> _rawEmployees = [];
  // After role-based scoping (e.g. on-site admin → own branch only).
  List<UserModel> _allEmployees = [];
  // After role-scoping AND search/filter chip.
  List<UserModel> _filteredEmployees = [];
  bool _isLoading = true;
  // Set while a background refresh is in flight after we've already shown
  // cached data — drives the thin progress bar.
  bool _isRefreshing = false;
  final TextEditingController _searchController = TextEditingController();
  int _currentPage = 0;
  static const int _rowsPerPage = 10;

  // Default to the Manager filter so the screen opens on a small, focused list
  // instead of rendering every employee. The user can switch to 'All' anytime.
  String _selectedRole = 'Manager';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEmployees();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    if (!mounted) return;

    // 1. Show the cached list IMMEDIATELY if we have one — no spinner, no
    //    blank screen. This is the main reason this screen used to feel slow.
    final cached = _EmployeesCache.get();
    if (cached != null) {
      _rawEmployees = cached;
      setState(() {
        _isLoading = false;
        _isRefreshing = true; // background refresh starts below
      });
      _applyRoleFiltering();
    } else {
      setState(() => _isLoading = true);
    }

    // 2. Always re-fetch in the background to pick up new employees / role
    //    changes. The cached list stays on screen during the request.
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;

      if (token == null) {
        throw Exception('You are not logged in. Please login again.');
      }

      final response = await ApiService.getEmployees(token);
      if (response.isSuccess && response.data != null) {
        final employees = ApiService.parseEmployeesFromResponse(response.data!);
        _EmployeesCache.set(employees);
        _rawEmployees = employees;
        _applyRoleFiltering();
      } else {
        throw Exception(response.error ?? 'Failed to load employees');
      }
    } catch (e) {
      print('Error loading employees: $e');
      // Suppress error toast if we successfully showed cached data — the user
      // already sees a working list. Surface only on hard-fail (no cache).
      if (mounted && cached == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  void _applyRoleFiltering() {
    final currentUser = Provider.of<AuthProvider>(
      context,
      listen: false,
    ).currentUser;
    if (currentUser == null) return;

    final role = currentUser.role;

    // Filter based on role

    List<UserModel> roleFilteredList = [];

    if (role == UserRole.director ||
        role == UserRole.admin ||
        role == UserRole.hoHr ||
        role == UserRole.hrAdmin) {
      // Sees all employees
      roleFilteredList = _rawEmployees;
    } else if (role == UserRole.onSiteAdmin || role == UserRole.manager) {
      // Onsite manager sees only onsite employees (same branch)
      roleFilteredList = _rawEmployees
          .where((e) => e.branchId == currentUser.branchId)
          .toList();
    } else {
      // Standard employee sees only themselves
      roleFilteredList = _rawEmployees
          .where((e) => e.id == currentUser.id)
          .toList();
    }

    setState(() {
      _allEmployees = roleFilteredList;
      _filterEmployees(); // Apply search and role filter chip
    });
  }

  void _onSearchChanged() {
    _filterEmployees();
  }

  void _filterEmployees() {
    setState(() {
      _filteredEmployees = _allEmployees.where((employee) {
        final matchesSearch =
            employee.fullName.toLowerCase().contains(
              _searchController.text.toLowerCase(),
            ) ||
            (employee.employeeId?.toLowerCase().contains(
                  _searchController.text.toLowerCase(),
                ) ??
                false);
        final matchesRole =
            _selectedRole == 'All' ||
            employee.role.displayName == _selectedRole;
        return matchesSearch && matchesRole;
      }).toList();
      _currentPage = 0; // Reset to first page on filter change
    });
  }

  List<UserModel> get _paginatedEmployees {
    final startIndex = _currentPage * _rowsPerPage;
    if (startIndex >= _filteredEmployees.length) return [];
    final endIndex = (startIndex + _rowsPerPage < _filteredEmployees.length)
        ? startIndex + _rowsPerPage
        : _filteredEmployees.length;
    return _filteredEmployees.sublist(startIndex, endIndex);
  }

  int _getRoleCount(String role) {
    if (role == 'All') return _allEmployees.length;
    return _allEmployees.where((e) => e.role.displayName == role).length;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text(
          'Employee Details',
          style: AppTextStyles.headlineMedium.copyWith(
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            color: isDark ? Colors.white : AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CustomLoader(size: 60))
          : Column(
              children: [
                // Inline progress bar — only visible while a background
                // refresh is happening after the cached list rendered. Same
                // pattern as Leave Summary / Team Overview.
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  child: _isRefreshing
                      ? LinearProgressIndicator(
                          minHeight: 2,
                          backgroundColor:
                              AppColors.primary.withOpacity(0.1),
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.primary),
                        )
                      : const SizedBox(height: 0),
                ),
                _buildSearchAndFilters(isDark),
                Expanded(
                  child: _filteredEmployees.isEmpty
                      ? _buildEmptyState(isDark)
                      : Column(
                          children: [
                            Expanded(child: _buildResponsiveTable(isDark)),
                            _buildPaginationControls(isDark),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSearchAndFilters(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name or ID...',
              prefixIcon: const Icon(Iconsax.search_normal, size: 20),
              filled: true,
              fillColor: isDark
                  ? AppColors.darkBackground
                  : AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Manager', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Admin', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('HR Admin', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('HO HR', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('On-site Admin', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Staff', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Employee', isDark),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1, end: 0);
  }

  Widget _buildFilterChip(String role, bool isDark) {
    final isSelected = _selectedRole == role;
    
    final int count = _getRoleCount(role);
    final String displayText = count > 0 ? '$role ($count)' : role;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedRole = role;
          _filterEmployees();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient : null,
          color: isSelected
              ? null
              : (isDark ? AppColors.darkBackground : AppColors.background),
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                ),
        ),
        child: Text(
          displayText,
          style: AppTextStyles.labelMedium.copyWith(
            color: isSelected
                ? Colors.white
                : (isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveTable(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              isDark
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : AppColors.primary.withValues(alpha: 0.05),
            ),
            dataRowMinHeight: 80,
            dataRowMaxHeight: 90,
            columnSpacing: 16,
            horizontalMargin: 12,
            showCheckboxColumn: false,
            columns: [
              DataColumn(label: Text('ID', style: AppTextStyles.labelLarge)),
              DataColumn(label: Text('Name', style: AppTextStyles.labelLarge)),
            ],
            rows: _paginatedEmployees.map((employee) {
              return DataRow(
                onSelectChanged: (_) {
                  _showEmployeeActions(context, employee);
                },
                cells: [
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.employeeId != null ? '#${employee.employeeId}' : 'N/A',
                          style: AppTextStyles.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          employee.isActive ? 'Active' : 'Inactive',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 10,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          child: Text(
                            employee.initials,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                employee.fullName,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${employee.designation ?? 'N/A'} • ${employee.department ?? 'N/A'} • ${employee.role.displayName}',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.textTertiary,
                                  fontSize: 10,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    ).animate().fadeIn().slideX(begin: 0.05, end: 0);
  }

  Widget _buildPaginationControls(bool isDark) {
    final int totalPages = (_filteredEmployees.length / _rowsPerPage).ceil();
    final bool hasNext = _currentPage < totalPages - 1;
    final bool hasPrev = _currentPage > 0;

    if (totalPages <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous Button
          TextButton.icon(
            onPressed: hasPrev
                ? () {
                    setState(() {
                      _currentPage--;
                    });
                  }
                : null,
            icon: const Icon(Icons.chevron_left, size: 16),
            label: const Text('Previous'),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white : AppColors.textPrimary,
              disabledForegroundColor: AppColors.textTertiary.withOpacity(0.5),
            ),
          ),

          // Page Info
          Text(
            'Page ${_currentPage + 1} of $totalPages',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),

          // Next Button
          TextButton.icon(
            onPressed: hasNext
                ? () {
                    setState(() {
                      _currentPage++;
                    });
                  }
                : null,
            icon: const Icon(Iconsax.arrow_right, size: 16),
            label: const Text('Next'),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white : AppColors.textPrimary,
              disabledForegroundColor: AppColors.textTertiary.withOpacity(0.5),
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
          Icon(
            Iconsax.user_remove,
            size: 64,
            color: AppColors.textTertiary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No employees found',
            style: AppTextStyles.headlineSmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filters',
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  void _showEmployeeActions(BuildContext context, UserModel employee) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: Text(
                      employee.initials,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.fullName,
                          style: AppTextStyles.titleLarge,
                        ),
                        Text(
                          '#${employee.employeeId} | ${employee.role.displayName}',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildActionTile(
                context: context,
                icon: Iconsax.user,
                title: 'View Profile',
                subtitle: 'See personal and work details',
                color: AppColors.info,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(user: employee),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              if (widget.showApplyLeave) ...[
                _buildActionTile(
                  context: context,
                  icon: Iconsax.calendar_tick,

                  title: 'Apply Leave',
                  subtitle: 'Request leave for this employee',
                  color: AppColors.warning,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LeaveScreen(targetUser: employee),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.titleMedium),
                  Text(subtitle, style: AppTextStyles.labelSmall),
                ],
              ),
            ),
            Icon(
              Iconsax.arrow_right,
              size: 14,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
