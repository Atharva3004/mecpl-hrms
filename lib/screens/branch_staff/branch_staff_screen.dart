import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';

class BranchStaffScreen extends StatefulWidget {
  const BranchStaffScreen({super.key});

  @override
  State<BranchStaffScreen> createState() => _BranchStaffScreenState();
}

class _BranchStaffScreenState extends State<BranchStaffScreen> {
  String role = "";
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = "ALL";

  // Branches the director can switch between (matches the requisition form set).
  static const List<String> _branches = ['Pune', 'Mumbai', 'Delhi', 'Hyderabad'];
  String _selectedBranch = _branches.first;

  // Dummy staff data — grouped by branch.
  // TODO: wire to ApiService.getEmployeesByBranch once the backend is ready.
  final List<Map<String, dynamic>> _allStaff = [
    // ── Pune ──
    {
      "name": "Abhijeet Patil",
      "empCode": "1101",
      "designation": "Site Engineer",
      "department": "Projects",
      "mobile": "9876543210",
      "status": "ACTIVE",
      "joiningDate": "01 Jan 2022",
      "branch": "Pune",
    },
    {
      "name": "Sneha Kulkarni",
      "empCode": "1102",
      "designation": "Supervisor",
      "department": "Operations",
      "mobile": "9876543211",
      "status": "ACTIVE",
      "joiningDate": "15 Mar 2023",
      "branch": "Pune",
    },
    {
      "name": "Rohan Deshmukh",
      "empCode": "1103",
      "designation": "Account Executive",
      "department": "Accounts",
      "mobile": "9876543212",
      "status": "INACTIVE",
      "joiningDate": "10 Sep 2020",
      "branch": "Pune",
    },
    {
      "name": "Priya Sharma",
      "empCode": "1104",
      "designation": "HR Coordinator",
      "department": "HR",
      "mobile": "9876543213",
      "status": "ACTIVE",
      "joiningDate": "12 Aug 2023",
      "branch": "Pune",
    },
    // ── Mumbai ──
    {
      "name": "Vikram Singh",
      "empCode": "1201",
      "designation": "Project Manager",
      "department": "Projects",
      "mobile": "9876543214",
      "status": "ACTIVE",
      "joiningDate": "05 Jun 2021",
      "branch": "Mumbai",
    },
    {
      "name": "Anjali Mehta",
      "empCode": "1202",
      "designation": "QA Engineer",
      "department": "Q.A",
      "mobile": "9876543215",
      "status": "ACTIVE",
      "joiningDate": "20 Feb 2022",
      "branch": "Mumbai",
    },
    {
      "name": "Imran Shaikh",
      "empCode": "1203",
      "designation": "Store Keeper",
      "department": "Stores",
      "mobile": "9876543216",
      "status": "INACTIVE",
      "joiningDate": "11 Nov 2019",
      "branch": "Mumbai",
    },
    // ── Delhi ──
    {
      "name": "Karan Malhotra",
      "empCode": "1301",
      "designation": "Site Engineer",
      "department": "Execution",
      "mobile": "9876543217",
      "status": "ACTIVE",
      "joiningDate": "03 Jul 2022",
      "branch": "Delhi",
    },
    {
      "name": "Ritu Verma",
      "empCode": "1302",
      "designation": "Electrician",
      "department": "Maintenance & Electrical",
      "mobile": "9876543218",
      "status": "ACTIVE",
      "joiningDate": "28 Apr 2023",
      "branch": "Delhi",
    },
    {
      "name": "Suresh Yadav",
      "empCode": "1303",
      "designation": "Supervisor",
      "department": "Operations",
      "mobile": "9876543219",
      "status": "ACTIVE",
      "joiningDate": "16 Dec 2021",
      "branch": "Delhi",
    },
    // ── Hyderabad ──
    {
      "name": "Lakshmi Reddy",
      "empCode": "1401",
      "designation": "Account Executive",
      "department": "Accounts",
      "mobile": "9876543220",
      "status": "ACTIVE",
      "joiningDate": "09 Jan 2023",
      "branch": "Hyderabad",
    },
    {
      "name": "Arjun Rao",
      "empCode": "1402",
      "designation": "Jr. Engineer",
      "department": "Execution",
      "mobile": "9876543221",
      "status": "INACTIVE",
      "joiningDate": "22 Oct 2020",
      "branch": "Hyderabad",
    },
    {
      "name": "Divya Nair",
      "empCode": "1403",
      "designation": "HR Coordinator",
      "department": "HR",
      "mobile": "9876543222",
      "status": "ACTIVE",
      "joiningDate": "07 May 2023",
      "branch": "Hyderabad",
    },
  ];

  List<Map<String, dynamic>> _filteredStaff = [];

  @override
  void initState() {
    super.initState();
    _loadRoleAndBranch();
    _applyFilters();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRoleAndBranch() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      role = (prefs.getString("role") ?? "").toUpperCase();
    });
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    final filter = _statusFilter;

    setState(() {
      _filteredStaff = _allStaff.where((staff) {
        final matchesBranch = staff["branch"] == _selectedBranch;

        final matchesSearch =
            query.isEmpty ||
            staff["name"].toString().toLowerCase().contains(query) ||
            staff["empCode"].toString().toLowerCase().contains(query);

        final matchesStatus = filter == "ALL"
            ? true
            : staff["status"].toString().toUpperCase() == filter;

        return matchesBranch && matchesSearch && matchesStatus;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Collapsing App Bar
          _buildSliverAppBar(context, isDark),

          // Branch selector, search and filters
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBranchSelector(isDark),
                  const SizedBox(height: 14),
                  _buildSearchField(isDark),
                  const SizedBox(height: 16),
                  _buildFilterChips(isDark),
                  const SizedBox(height: 14),
                  Text(
                    '${_filteredStaff.length} staff in $_selectedBranch',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Staff List
          if (_filteredStaff.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(isDark),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final staff = _filteredStaff[index];
                  return _buildStaffCard(context, staff, isDark, index);
                }, childCount: _filteredStaff.length),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, bool isDark) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(
          Icons.chevron_left,
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Branch Staff',
        style: GoogleFonts.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );
  }

  // Horizontal branch picker — choose which branch's staff to view.
  Widget _buildBranchSelector(bool isDark) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _branches.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final branch = _branches[index];
          final isSelected = branch == _selectedBranch;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedBranch = branch;
                _applyFilters();
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark
                          ? AppColors.primary.withOpacity(0.8)
                          : AppColors.primary)
                    : (isDark ? AppColors.darkSurface : Colors.white),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkBorder : AppColors.border),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  Icon(
                    Iconsax.building_4,
                    size: 14,
                    color: isSelected
                        ? Colors.white
                        : (isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    branch,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : (isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).animate().fadeIn().slideX(begin: -0.1, end: 0);
  }

  Widget _buildSearchField(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.inter(
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Search by name or emp code...',
          hintStyle: GoogleFonts.inter(
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.textTertiary,
          ),
          prefixIcon: Icon(
            Iconsax.search_status,
            color: isDark ? AppColors.primaryLight : AppColors.primary,
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 15,
          ),
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildFilterChips(bool isDark) {
    return Row(
      children: [
        _filterChip("ALL", "All", isDark),
        const SizedBox(width: 8),
        _filterChip("ACTIVE", "Active", isDark),
        const SizedBox(width: 8),
        _filterChip("INACTIVE", "Inactive", isDark),
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _filterChip(String value, String label, bool isDark) {
    final isSelected = _statusFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _statusFilter = value;
          _applyFilters();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                    ? AppColors.primary.withOpacity(0.8)
                    : AppColors.primary)
              : (isDark ? AppColors.darkSurface : Colors.white),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (isDark ? AppColors.darkBorder : AppColors.border),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildStaffCard(
    BuildContext context,
    Map<String, dynamic> staff,
    bool isDark,
    int index,
  ) {
    final isActive =
        (staff["status"] ?? "").toString().toUpperCase() == "ACTIVE";
    final statusColor = isActive ? AppColors.success : AppColors.error;

    return Container(
          margin: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border,
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  // Show details or navigate
                },
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Row(
                    children: [
                      // Profile Avatar
                      Stack(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                Iconsax.user,
                                color: statusColor,
                                size: 22,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 13,
                              height: 13,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark
                                      ? AppColors.darkSurface
                                      : Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 13),

                      // Staff Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              staff["name"] ?? "",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              "${staff["designation"]} • ${staff["department"]}",
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Iconsax.personalcard,
                                  size: 14,
                                  color: AppColors.primary.withOpacity(0.7),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  "Emp: ${staff["empCode"]}",
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white70
                                        : AppColors.textPrimary.withOpacity(
                                            0.7,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isActive ? "Active" : "Inactive",
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
        .animate(delay: Duration(milliseconds: 50 * index))
        .fadeIn()
        .slideY(begin: 0.1, end: 0);
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Iconsax.user_search,
              size: 64,
              color: AppColors.primary.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No staff members found',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters or search query',
            style: GoogleFonts.inter(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }
}
