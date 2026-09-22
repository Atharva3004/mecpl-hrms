// Departments — read-only list of all departments with their staff counts.
// Each department expands inline to reveal the staff in that department.
//
// NOTE: Runs on in-memory MOCK data (see `_staff`). Swap for an ApiService call
// once the backend exposes a departments / employees endpoint.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  // Department keys the user expanded. While a search is active every shown
  // department is forced open (see _isOpen).
  final Set<String> _expanded = {};

  // ---- MOCK DATA (replace with API once available) -----------------------
  // Each staff row carries its department; the screen groups by department.
  final List<Map<String, String>> _staff = [
    {'name': 'Abhijeet Patil', 'designation': 'Site Engineer', 'department': 'Projects'},
    {'name': 'Vikram Singh', 'designation': 'Project Manager', 'department': 'Projects'},
    {'name': 'Karan Malhotra', 'designation': 'Site Engineer', 'department': 'Execution'},
    {'name': 'Arjun Rao', 'designation': 'Jr. Engineer', 'department': 'Execution'},
    {'name': 'Sneha Kulkarni', 'designation': 'Supervisor', 'department': 'Operations'},
    {'name': 'Suresh Yadav', 'designation': 'Supervisor', 'department': 'Operations'},
    {'name': 'Rohan Deshmukh', 'designation': 'Account Executive', 'department': 'Accounts'},
    {'name': 'Lakshmi Reddy', 'designation': 'Account Executive', 'department': 'Accounts'},
    {'name': 'Priya Sharma', 'designation': 'HR Coordinator', 'department': 'HR'},
    {'name': 'Divya Nair', 'designation': 'HR Coordinator', 'department': 'HR'},
    {'name': 'Anjali Mehta', 'designation': 'QA Engineer', 'department': 'Q.A'},
    {'name': 'Imran Shaikh', 'designation': 'Store Keeper', 'department': 'Stores'},
    {'name': 'Ritu Verma', 'designation': 'Electrician', 'department': 'Maintenance & Electrical'},
  ];

  List<Map<String, String>> get _filtered {
    if (_query.isEmpty) return _staff;
    final q = _query.toLowerCase();
    return _staff
        .where((s) =>
            s['department']!.toLowerCase().contains(q) ||
            s['name']!.toLowerCase().contains(q) ||
            s['designation']!.toLowerCase().contains(q))
        .toList();
  }

  // Filtered staff grouped by department, preserving first-seen order.
  Map<String, List<Map<String, String>>> get _grouped {
    final map = <String, List<Map<String, String>>>{};
    for (final s in _filtered) {
      map.putIfAbsent(s['department']!, () => []).add(s);
    }
    return map;
  }

  bool _isOpen(String dept) => _query.isNotEmpty || _expanded.contains(dept);

  void _toggle(String dept) {
    setState(() {
      if (_expanded.contains(dept)) {
        _expanded.remove(dept);
      } else {
        _expanded.add(dept);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _grouped;
    final deptKeys = groups.keys.toList();
    final totalStaff = _filtered.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Departments',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: AppTextStyles.bodySmall,
              decoration: InputDecoration(
                hintText: 'Search department, name, designation…',
                hintStyle: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
                prefixIcon: const Icon(Iconsax.search_normal, size: 16),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          // Summary banner
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text(
                  '${deptKeys.length} department${deptKeys.length == 1 ? '' : 's'} · $totalStaff staff',
                  style: AppTextStyles.labelMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: deptKeys.isEmpty
                ? Center(
                    child: Text(
                      'No departments found',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: deptKeys.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final dept = deptKeys[index];
                      return _buildDeptCard(dept, groups[dept]!, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // One department card: tappable header (name + staff count) that expands
  // inline to list the department's staff.
  Widget _buildDeptCard(
    String dept,
    List<Map<String, String>> staff,
    int index,
  ) {
    final open = _isOpen(dept);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: AppColors.primary, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _toggle(dept),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Iconsax.buildings_2,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        dept,
                        style: AppTextStyles.titleSmall.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${staff.length} staff',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 9),
              child: Column(
                children: [
                  for (var i = 0; i < staff.length; i++) ...[
                    if (i > 0) Divider(height: 14, color: AppColors.border),
                    _buildStaffRow(staff[i]),
                  ],
                ],
              ),
            ),
            crossFadeState:
                open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    ).animate(delay: (index * 40).ms).fadeIn(duration: 250.ms).slideY(
          begin: 0.05,
          end: 0,
          duration: 250.ms,
        );
  }

  Widget _buildStaffRow(Map<String, String> s) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Iconsax.user, size: 14, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s['name']!,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                s['designation']!,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
