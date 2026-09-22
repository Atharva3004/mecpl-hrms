import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import 'payslip_full_screen.dart';
import 'widgets/payslip_pdf_view.dart';

class EmployeePayslipScreen extends StatefulWidget {
  const EmployeePayslipScreen({super.key});

  @override
  State<EmployeePayslipScreen> createState() => _EmployeePayslipScreenState();
}

class _EmployeePayslipScreenState extends State<EmployeePayslipScreen> {
  UserModel? _selectedEmployee;
  String _selectedYear = '2026';
  String _selectedMonth = 'January';

  List<UserModel> _employees = [];

  bool _isLoadingPayslip = false;
  String? _errorMessage;
  Map<String, dynamic>? _payslipData;

  // Cached path of the inline-preview PDF so Share + Download reuse it
  // without a second network round-trip. Reset on every selection change.
  String? _cachedPdfPath;

  final List<String> _years = ['2026', '2025', '2024'];
  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null) {
      setState(() {
        _errorMessage = 'Not authenticated. Please login again.';
      });
      return;
    }

    try {
      final response = await ApiService.getEmployees(token);
      if (response.isSuccess && response.data != null) {
        final employees = ApiService.parseEmployeesFromResponse(response.data!);
        if (mounted)
          setState(() {
            _employees = employees;
          });
      } else {
        setState(() {
          _errorMessage = response.error ?? 'Failed to load employees';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading employees: $e';
      });
    }
  }

  Future<void> _fetchPayslip() async {
    if (_selectedEmployee == null) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null) {
      if (mounted)
        setState(() {
          _errorMessage = 'Not authenticated. Please login again.';
        });
      return;
    }

    if (mounted)
      setState(() {
        _isLoadingPayslip = true;
        _errorMessage = null;
        _payslipData = null;
        _cachedPdfPath = null;
      });

    try {
      final processMonth = '$_selectedMonth $_selectedYear';
      debugPrint(
        '📤 [Payslip] Fetching for emp_id: ${_selectedEmployee!.id}, month: $processMonth',
      );
      final response = await ApiService.getEmployeePayslip(
        token: token,
        empId: _selectedEmployee!.id,
        processMonth: processMonth,
        payslipType: 'employee',
      );

      debugPrint(
        '📥 [Payslip] Success: ${response.isSuccess}, Error: ${response.error}',
      );

      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        debugPrint(
          '📥 [Payslip] Status: ${data['status']}, Data length: ${(data['data'] as List?)?.length ?? 0}',
        );
        if (data['status'] == true &&
            data['data'] != null &&
            (data['data'] as List).isNotEmpty) {
          if (mounted)
            setState(() {
              _payslipData = data['data'][0] as Map<String, dynamic>;
              _isLoadingPayslip = false;
            });
        } else {
          if (mounted)
            setState(() {
              _isLoadingPayslip = false;
              _errorMessage =
                  data['message']?.toString() ??
                  'No payslip data found for $_selectedMonth $_selectedYear';
            });
        }
      } else {
        if (mounted)
          setState(() {
            _isLoadingPayslip = false;
            _errorMessage = response.error ?? 'Failed to fetch payslip';
          });
      }
    } catch (e) {
      debugPrint('❌ [Payslip] Error: $e');
      if (mounted)
        setState(() {
          _isLoadingPayslip = false;
          _errorMessage = 'Error fetching payslip: $e';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildAppBar(context, isDark),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildFiltersCard(isDark),
                  if (_isLoadingPayslip) ...[
                    const SizedBox(height: 40),
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 20),
                  ] else if (_errorMessage != null &&
                      _selectedEmployee != null) ...[
                    const SizedBox(height: 20),
                    _buildErrorWidget(isDark),
                  ] else if (_payslipData != null) ...[
                    const SizedBox(height: 20),
                    _buildPreviewLabel(isDark),
                    const SizedBox(height: 10),
                    _buildPdfPreview(),
                    const SizedBox(height: 20),
                    _buildActionRow(),
                  ],
                  const SizedBox(height: 40),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Error Widget ──────────────────────────────────────────────────────
  Widget _buildErrorWidget(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Column(
        children: [
          const Icon(Iconsax.info_circle, color: Color(0xFFF43F5E), size: 36),
          const SizedBox(height: 10),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: _fetchPayslip,
            icon: const Icon(Iconsax.refresh, size: 16),
            label: const Text('Retry'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  // ── AppBar ──────────────────────────────────────────────────────────────
  Widget _buildAppBar(BuildContext context, bool isDark) {
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
        'Employee Payslip',
        style: AppTextStyles.headlineLarge.copyWith(
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildFiltersCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        children: [
          // Employee selector
          _buildEmployeeDropdown(isDark),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDropdownField(
                  label: 'YEAR',
                  value: _selectedYear,
                  items: _years,
                  onChanged: (v) {
                    setState(() {
                      _selectedYear = v!;
                    });
                    _fetchPayslip();
                  },
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDropdownField(
                  label: 'MONTH',
                  value: _selectedMonth,
                  items: _months,
                  onChanged: (v) {
                    setState(() {
                      _selectedMonth = v!;
                    });
                    _fetchPayslip();
                  },
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildEmployeeDropdown(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SELECT EMPLOYEE',
          style: AppTextStyles.labelSmall.copyWith(
            color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _showEmployeeSearchSheet(isDark),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                  width: 1.0,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedEmployee != null
                        ? '${_selectedEmployee!.fullName} (${_selectedEmployee!.employeeId ?? "N/A"})'
                        : 'Search or choose an employee...',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: _selectedEmployee != null
                          ? (isDark ? Colors.white : AppColors.textPrimary)
                          : (isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.textTertiary),
                      fontWeight: _selectedEmployee != null
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.search,
                  size: 18,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showEmployeeSearchSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = _employees.where((emp) {
              final name = emp.fullName.toLowerCase();
              final code = (emp.employeeId ?? '').toLowerCase();
              final q = query.toLowerCase();
              return name.contains(q) || code.contains(q);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search employee...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: isDark
                              ? AppColors.darkBackground
                              : AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                _employees.isEmpty
                                    ? 'Loading employees...'
                                    : 'No matches found',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white54
                                      : AppColors.textTertiary,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: filtered.length,
                              itemBuilder: (_, index) {
                                final emp = filtered[index];
                                final label =
                                    '${emp.fullName} (${emp.employeeId ?? "N/A"})';
                                return ListTile(
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppColors.primary
                                        .withOpacity(0.1),
                                    child: Text(
                                      emp.initials,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    emp.department ?? '',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.white54
                                          : AppColors.textTertiary,
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    setState(() {
                                      _selectedEmployee = emp;
                                    });
                                    _fetchPayslip();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.border,
                width: 1.0,
              ),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              isDense: true,
              dropdownColor: isDark ? AppColors.darkSurface : Colors.white,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.textTertiary,
              ),
              style: AppTextStyles.bodyLarge.copyWith(
                color: isDark ? Colors.white : AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              onChanged: onChanged,
              items: items
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ── Preview Label ──────────────────────────────────────────────────────
  Widget _buildPreviewLabel(bool isDark) {
    return Text(
      'PREVIEW',
      style: AppTextStyles.labelLarge.copyWith(
        color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
        letterSpacing: 1.2,
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  // ── PDF Preview (inline, real backend PDF) ────────────────────────────
  Widget _buildPdfPreview() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token ?? '';
    final empId = _selectedEmployee?.id ?? '';
    final processMonth = '$_selectedMonth $_selectedYear';
    final cacheKey = 'emp_${empId}_$processMonth';
    final heroTag = 'payslip-hero-$cacheKey';

    return PayslipPdfView(
      cacheKey: cacheKey,
      heroTag: heroTag,
      loader: buildApiPayslipLoader(
        token: token,
        processMonth: processMonth,
        empId: empId,
        payslipType: 'employee',
      ),
      onReady: (path) {
        if (!mounted) return;
        setState(() => _cachedPdfPath = path);
      },
      onTap: () => _openFullScreen(heroTag, processMonth),
    );
  }

  void _openFullScreen(String heroTag, String processMonth) {
    final path = _cachedPdfPath;
    if (path == null) return;
    final empLabel = _selectedEmployee?.fullName ?? 'Employee';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PayslipFullScreen(
          filePath: path,
          heroTag: heroTag,
          title: 'Payslip — $processMonth',
          shareSubject: '$empLabel Payslip — $processMonth',
          onDownload: _downloadPayslipPdf,
        ),
      ),
    );
  }

  // ── Action row: Download + Share ─────────────────────────────────────
  Widget _buildActionRow() {
    final ready = _cachedPdfPath != null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isDownloading ? null : _downloadPayslipPdf,
            icon: _isDownloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Iconsax.document_download, size: 18),
            label: Text(
              _isDownloading ? 'Downloading...' : 'Download PDF',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: ready ? _sharePayslip : null,
            icon: const Icon(Iconsax.share, size: 18),
            label: const Text(
              'Share',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(
                color: ready
                    ? AppColors.primary
                    : AppColors.primary.withOpacity(0.4),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _sharePayslip() async {
    final path = _cachedPdfPath;
    if (path == null) return;
    final processMonth = '$_selectedMonth $_selectedYear';
    final empLabel = _selectedEmployee?.fullName ?? 'Employee';
    try {
      await Share.shareXFiles(
        [XFile(path, mimeType: 'application/pdf')],
        subject: '$empLabel Payslip — $processMonth',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open share sheet')),
      );
    }
  }

  // Legacy hand-rendered preview kept for reference; no longer wired in.
  // ignore: unused_element
  Widget _buildPayslipPreview(bool isDark) {
    final payslip = _payslipData!;
    final calculated =
        payslip['calculated_payslip'] as Map<String, dynamic>? ?? {};
    final earnings = (calculated['earnings'] as List<dynamic>?) ?? [];
    final deductions = (calculated['deductions'] as List<dynamic>?) ?? [];
    final grossTotal = (calculated['gross_total'] ?? 0).toDouble();
    final deductionTotal = (calculated['deduction_total'] ?? 0).toDouble();
    final netPay = (calculated['net_pay'] ?? 0).toDouble();

    // Employee info
    final empName = payslip['emp_name']?.toString() ?? 'N/A';
    final companyDetails =
        payslip['company_details'] as Map<String, dynamic>? ?? {};
    final empCode = companyDetails['emp_code']?.toString() ?? 'N/A';
    final deptObj = companyDetails['department'];
    final deptName = (deptObj is Map)
        ? (deptObj['department_name']?.toString() ?? 'N/A')
        : 'N/A';

    // Salary summary status
    final salSummary = payslip['salary_summary_details'] as List<dynamic>?;
    final status = (salSummary != null && salSummary.isNotEmpty)
        ? salSummary[0]['status']?.toString() ?? ''
        : '';
    final paidDays = (salSummary != null && salSummary.isNotEmpty)
        ? (salSummary[0]['payable_days'] ?? salSummary[0]['paid_days'] ?? 'N/A').toString()
        : 'N/A';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Employee Info ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Employee Name - Full name in two lines, no card
                Text(
                  'Employee',
                  style: TextStyle(
                    fontSize: 9,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  empName,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white : const Color(0xFF4F46E5),
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                // ID, Dept, and Paid Days in a row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ID',
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark
                                  ? Colors.white54
                                  : const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            empCode,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0891B2),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dept',
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark
                                  ? Colors.white54
                                  : const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            deptName,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF059669),
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Paid Days',
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark
                                  ? Colors.white54
                                  : const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            paidDays,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFFD97706),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, indent: 18, endIndent: 18),

          // ── Mini Earnings / Deductions Table ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Earnings column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTableHeader('Earnings', const Color(0xFF10B981)),
                      const SizedBox(height: 8),
                      ...earnings.map((e) {
                        final label = e['label']?.toString() ?? '';
                        final amount =
                            (e['earned_amount'] ?? e['actual_amount'] ?? 0)
                                .toDouble();
                        return _buildTableRow(
                          label,
                          _currencyFormat.format(amount),
                        );
                      }),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                              ),
                            ),
                            Text(
                              _currencyFormat.format(grossTotal),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height:
                      40.0 +
                      (earnings.length > deductions.length
                              ? earnings.length
                              : deductions.length) *
                          24.0,
                  color: const Color(0xFFE8E8E8),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),
                // Deductions column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTableHeader('Deductions', const Color(0xFFF43F5E)),
                      const SizedBox(height: 8),
                      ...deductions.map((d) {
                        final label = d['label']?.toString() ?? '';
                        final amount = (d['amount'] ?? 0).toDouble();
                        return _buildTableRow(
                          label,
                          _currencyFormat.format(amount),
                        );
                      }),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF43F5E).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFF43F5E),
                              ),
                            ),
                            Text(
                              _currencyFormat.format(deductionTotal),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFF43F5E),
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
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, indent: 18, endIndent: 18),

          // ── Net Pay Footer ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FF),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(13)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Net Pay',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currencyFormat.format(netPay),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4F46E5),
                      ),
                    ),
                  ],
                ),
                if (status.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: status == 'Finalized'
                          ? const Color(0xFF10B981).withOpacity(0.1)
                          : const Color(0xFFF59E0B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          status == 'Finalized'
                              ? Iconsax.tick_circle
                              : Iconsax.clock,
                          size: 14,
                          color: status == 'Finalized'
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: status == 'Finalized'
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B),
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
    ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.08, end: 0);
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                color: color.withOpacity(0.7),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTableRow(String label, String amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  // ── Download Button ────────────────────────────────────────────────────
  bool _isDownloading = false;

  Widget _buildDownloadButton() {
    return Center(
      child: SizedBox(
        width: 220,
        child: ElevatedButton.icon(
          onPressed: _isDownloading ? null : () => _downloadPayslipPdf(),
          icon: _isDownloading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Iconsax.document_download, size: 18),
          label: Text(
            _isDownloading ? 'Downloading...' : 'Download PDF',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
        ),
      ),
    ).animate().fadeIn(delay: 250.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Future<void> _downloadPayslipPdf() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null) return;

    setState(() => _isDownloading = true);

    final processMonth = '$_selectedMonth $_selectedYear';
    final empId = _selectedEmployee?.id ?? '';

    final filePath = await ApiService.downloadPayslip(
      token: token,
      processMonth: processMonth,
      empId: empId,
      payslipType: 'employee',
    );

    if (!mounted) return;
    setState(() => _isDownloading = false);

    if (filePath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Iconsax.tick_circle, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text('Saved to Downloads folder')),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          action: SnackBarAction(
            label: 'OPEN FILE',
            textColor: Colors.white,
            onPressed: () async {
              final result = await OpenFile.open(filePath);
              if (!mounted) return;
              if (result.type != ResultType.done) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result.message)),
                );
              }
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Iconsax.warning_2, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              const Expanded(child: Text('Failed to download payslip')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }
}
