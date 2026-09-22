import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import 'payslip_full_screen.dart';
import 'widgets/payslip_pdf_view.dart';

class DownloadSlipsScreen extends StatefulWidget {
  const DownloadSlipsScreen({super.key});

  @override
  State<DownloadSlipsScreen> createState() => _DownloadSlipsScreenState();
}

class _DownloadSlipsScreenState extends State<DownloadSlipsScreen> {
  String _selectedYear = '2026';
  String _selectedMonth = 'January';

  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _payslipData;

  // Cached path of the currently-rendered PDF preview. Set by
  // PayslipPdfView.onReady; cleared when the user re-selects month/year.
  // Reused by Share + Download so neither has to re-hit the network.
  String? _cachedPdfPath;

  final List<String> _years = ['2026', '2025', '2024'];
  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  Future<void> _fetchPayslip() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    final empId = auth.currentUser?.id ?? auth.currentUser?.employeeId ?? '';

    if (token == null || token.isEmpty) {
      setState(() => _errorMessage = 'You are not logged in. Please log in again.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _payslipData = null;
      _cachedPdfPath = null;
    });

    final processMonth = '$_selectedMonth $_selectedYear';

    final response = await ApiService.getEmployeePayslip(
      token: token,
      empId: empId,
      processMonth: processMonth,
    );

    if (!mounted) return;

    if (response.isSuccess && response.data != null) {
      final data = response.data!;

      // Check if HTML login page was returned (session expired)
      final rawData = data['data'];
      if (rawData is String && (rawData.contains('<html') || rawData.contains('<!doctype'))) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Session expired. Please log out and log in again.';
        });
        return;
      }

      // Check API status
      if (data['status'] == true && data['data'] != null) {
        final List<dynamic> dataList = data['data'];
        if (dataList.isNotEmpty) {
          setState(() {
            _isLoading = false;
            _payslipData = Map<String, dynamic>.from(dataList[0]);
          });
          return;
        }
      }

      setState(() {
        _isLoading = false;
        _errorMessage = data['message']?.toString() ?? 'No payslip data found for this month.';
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = response.error ?? 'Failed to fetch payslip.';
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
                  const SizedBox(height: 16),
                  _buildFetchButton(isDark),
                  if (_isLoading) ...[
                    const SizedBox(height: 32),
                    _buildLoadingState(),
                  ] else if (_errorMessage != null) ...[
                    const SizedBox(height: 24),
                    _buildErrorState(isDark),
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

  Widget _buildAppBar(BuildContext context, bool isDark) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.chevron_left, color: isDark ? Colors.white : AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'My Payslip',
        style: AppTextStyles.headlineLarge.copyWith(
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildFiltersCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildDropdownField(label: 'YEAR', value: _selectedYear, items: _years, onChanged: (v) => setState(() => _selectedYear = v!), isDark: isDark),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _buildDropdownField(label: 'MONTH', value: _selectedMonth, items: _months, onChanged: (v) => setState(() => _selectedMonth = v!), isDark: isDark),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildFetchButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _fetchPayslip,
        icon: const Icon(Iconsax.eye, size: 18),
        label: Text(
          'View Payslip',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
    ).animate().fadeIn(delay: 150.ms);
  }

  Widget _buildLoadingState() {
    return Column(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text('Fetching your payslip...', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textTertiary)),
      ],
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Iconsax.warning_2, color: Colors.red, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(_errorMessage ?? 'An error occurred.', style: const TextStyle(color: Colors.red, fontSize: 13))),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildDropdownField({required String label, required String value, required List<String> items, required ValueChanged<String?> onChanged, required bool isDark}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelSmall.copyWith(color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border, width: 1.5))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              isDense: true,
              dropdownColor: isDark ? AppColors.darkSurface : Colors.white,
              icon: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary),
              style: AppTextStyles.bodyLarge.copyWith(color: isDark ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w500),
              onChanged: onChanged,
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewLabel(bool isDark) {
    return Text(
      'PREVIEW',
      style: AppTextStyles.labelLarge.copyWith(color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary, letterSpacing: 1.2),
    ).animate().fadeIn(delay: 200.ms);
  }

  // ── PDF Preview (inline, real backend PDF) ────────────────────────────
  Widget _buildPdfPreview() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token ?? '';
    // Mirror the empId fallback used by _fetchPayslip / _downloadPayslipPdf
    // so the preview, the JSON fetch, and the eventual download all key off
    // the same employee identifier — otherwise the cached PDF won't match.
    final empId =
        auth.currentUser?.id ?? auth.currentUser?.employeeId ?? '';
    final processMonth = '$_selectedMonth $_selectedYear';
    final cacheKey = 'my_${empId}_$processMonth';
    final heroTag = 'payslip-hero-$cacheKey';

    return PayslipPdfView(
      cacheKey: cacheKey,
      heroTag: heroTag,
      loader: buildApiPayslipLoader(
        token: token,
        processMonth: processMonth,
        empId: empId,
        payslipType: '',
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PayslipFullScreen(
          filePath: path,
          heroTag: heroTag,
          title: 'Payslip — $processMonth',
          shareSubject: 'Payslip — $processMonth',
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
    try {
      await Share.shareXFiles(
        [XFile(path, mimeType: 'application/pdf')],
        subject: 'Payslip — $processMonth',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open share sheet')),
      );
    }
  }

  // Old hand-rendered preview kept here so other helpers can reach the
  // same data shape if needed in the future. Currently unused after the
  // preview was switched to the real backend PDF.
  // ignore: unused_element
  Widget _legacyHandRenderedPreview(bool isDark) {
    final data = _payslipData!;
    final calculated = data['calculated_payslip'] as Map<String, dynamic>? ?? {};
    final earnings = (calculated['earnings'] as List<dynamic>?) ?? [];
    final deductions = (calculated['deductions'] as List<dynamic>?) ?? [];
    final grossTotal = calculated['gross_total'];
    final deductionTotal = calculated['deduction_total'];
    final netPay = calculated['net_pay'];

    // Employee info
    final empName = data['emp_name']?.toString() ?? 'N/A';
    final companyDetails = data['company_details'] as Map<String, dynamic>? ?? {};
    final empCode = companyDetails['emp_code']?.toString() ?? 'N/A';
    final deptMap = companyDetails['department'] as Map<String, dynamic>? ?? {};
    final department = deptMap['short_name']?.toString() ?? deptMap['department_name']?.toString() ?? 'N/A';

    // Salary summary status
    final salSummary = data['salary_summary_details'] as List<dynamic>? ?? [];
    final status = salSummary.isNotEmpty ? (salSummary[0]['status']?.toString() ?? 'Processed') : 'Processed';
    final paidDays = data['paid_day']?.toString() ?? '';
    final ncpDays = data['ncp_days']?.toString() ?? '0';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // ── Employee Info ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                              color: isDark ? Colors.white54 : const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            empCode,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white : const Color(0xFF0891B2),
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
                              color: isDark ? Colors.white54 : const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            department,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white : const Color(0xFF059669),
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
                              color: isDark ? Colors.white54 : const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            paidDays.isNotEmpty ? paidDays : 'N/A',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white : const Color(0xFFD97706),
                              fontWeight: FontWeight.w600,
                            ),
                          ), // Using the style same as in employee payslip
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, indent: 18, endIndent: 18),

          // ── Earnings / Deductions Table ──
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
                        final amount = _formatAmount(e['earned_amount'] ?? e['actual_amount']);
                        return _buildTableRow(label, amount ?? '—');
                      }),
                      const SizedBox(height: 6),
                      if (grossTotal != null)
                        _buildTotalRow('Gross Total', _formatAmount(grossTotal) ?? '—', const Color(0xFF10B981)),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: (earnings.length > deductions.length ? earnings.length : deductions.length) * 22.0 + 60,
                  color: const Color(0xFFE8E8E8),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
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
                        final amount = _formatAmount(d['amount']);
                        return _buildTableRow(label, amount ?? '—');
                      }),
                      const SizedBox(height: 6),
                      if (deductionTotal != null)
                        _buildTotalRow('Total Ded.', _formatAmount(deductionTotal) ?? '—', const Color(0xFFF43F5E)),
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
                    const Text('Net Pay', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(
                      _formatAmount(netPay) ?? '—',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: status == 'Finalized' ? const Color(0xFF10B981).withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        status == 'Finalized' ? Iconsax.tick_circle : Iconsax.clock,
                        size: 14,
                        color: status == 'Finalized' ? const Color(0xFF10B981) : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: status == 'Finalized' ? const Color(0xFF10B981) : Colors.orange,
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
    ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.08, end: 0);
  }

  String? _formatAmount(dynamic value) {
    if (value == null) return null;
    final numVal = double.tryParse(value.toString());
    if (numVal == null) return null;
    return '₹${numVal.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 8, color: color.withOpacity(0.7), fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 1),
            Text(value, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5)),
    );
  }

  Widget _buildTableRow(String label, String amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis)),
          Text(amount, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, String amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
          Text(amount, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  bool _isDownloading = false;

  Widget _buildDownloadButton() {
    return Center(
      child: SizedBox(
        width: 220,
        child: ElevatedButton.icon(
          onPressed: _isDownloading ? null : () => _downloadPayslipPdf(),
          icon: _isDownloading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
      ),
    ).animate().fadeIn(delay: 350.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Future<void> _downloadPayslipPdf() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    final empId = auth.currentUser?.id ?? '';
    if (token == null) return;

    setState(() => _isDownloading = true);

    final processMonth = '$_selectedMonth $_selectedYear';

    final filePath = await ApiService.downloadPayslip(
      token: token,
      processMonth: processMonth,
      empId: empId,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }
}
