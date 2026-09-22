import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../models/regularization_request_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

class RegularizationListScreen extends StatefulWidget {
  const RegularizationListScreen({super.key});

  @override
  State<RegularizationListScreen> createState() =>
      _RegularizationListScreenState();
}

class _RegularizationListScreenState extends State<RegularizationListScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<RegularizationRequest> _requests = [];
  String _statusFilter = 'All'; // All, Pending, Approved, Rejected
  final Set<int> _expandedIndices = {};

  // Date range — default to last 45 days
  late DateTime _fromDate;
  late DateTime _toDate;

  // Counts returned from the API (fallback: compute client-side).
  int _apiTotal = 0;
  int _apiPending = 0;
  int _apiApproved = 0;
  int _apiRejected = 0;
  bool _hasApiCounts = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _toDate = DateTime(now.year, now.month, now.day);
    _fromDate = _toDate.subtract(const Duration(days: 45));
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final token = context.read<AuthProvider>().token;
      if (token == null) {
        setState(() {
          _errorMessage = 'Not authenticated';
          _isLoading = false;
        });
        return;
      }

      final df = DateFormat('yyyy-MM-dd');
      final response = await ApiService.getMyRegularizationList(
        token: token,
        fromDate: df.format(_fromDate),
        toDate: df.format(_toDate),
        status: 'All',
      );
      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        final dynamic rawData =
            data['data'] ?? data['requests'] ?? data['list'] ?? [];

        if (rawData is List) {
          _requests = rawData
              .map((json) {
                try {
                  return RegularizationRequest.fromJson(
                    json as Map<String, dynamic>,
                  );
                } catch (e) {
                  debugPrint('⚠️ Error parsing regularization request: $e');
                  return null;
                }
              })
              .whereType<RegularizationRequest>()
              .toList();
        } else {
          _requests = [];
        }

        // Use server-provided counts when available.
        final counts = data['counts'];
        if (counts is Map) {
          _hasApiCounts = true;
          _apiTotal = _toInt(counts['total']);
          _apiPending = _toInt(counts['pending']);
          _apiApproved = _toInt(counts['approved']);
          _apiRejected = _toInt(counts['rejected']);
        } else {
          _hasApiCounts = false;
        }
      } else {
        _requests = [];
        _hasApiCounts = false;
        _errorMessage = response.error;
      }
    } catch (e) {
      debugPrint('Error loading my regularization list: $e');
      _errorMessage = 'Something went wrong';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: AppConstants.appStartDate,
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _fromDate.isBefore(AppConstants.appStartDate)
            ? AppConstants.appStartDate
            : _fromDate,
        end: _toDate,
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF031633),
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() {
      _fromDate = picked.start;
      _toDate = picked.end;
    });
    _loadData();
  }

  List<RegularizationRequest> get _filteredRequests {
    if (_statusFilter == 'All') return _requests;
    return _requests.where((r) {
      return r.status.toLowerCase() == _statusFilter.toLowerCase();
    }).toList();
  }

  int _countByStatus(String status) {
    if (_hasApiCounts) {
      switch (status.toLowerCase()) {
        case 'pending':
          return _apiPending;
        case 'approved':
          return _apiApproved;
        case 'rejected':
          return _apiRejected;
      }
    }
    return _requests
        .where((r) => r.status.toLowerCase() == status.toLowerCase())
        .length;
  }

  int get _totalCount => _hasApiCounts ? _apiTotal : _requests.length;

  @override
  Widget build(BuildContext context) {
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
          'Regularization List',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Change date range',
            icon: const Icon(Iconsax.calendar, color: Colors.black87),
            onPressed: _pickDateRange,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF3F51B5)),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFF3F51B5),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const SizedBox(height: 8),
                  _buildDateRangeBar(),
                  const SizedBox(height: 10),
                  _buildSummaryCards(),
                  const SizedBox(height: 16),
                  _buildStatusFilterChips(),
                  const SizedBox(height: 12),
                  if (_filteredRequests.isEmpty)
                    _buildEmptyState()
                  else
                    ..._filteredRequests.asMap().entries.map((entry) {
                      return _buildRequestCard(entry.value, entry.key);
                    }),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildDateRangeBar() {
    final df = DateFormat('dd MMM yyyy');
    return InkWell(
      onTap: _pickDateRange,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            const Icon(Iconsax.calendar_1, size: 16, color: Color(0xFF3F51B5)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${df.format(_fromDate)}  —  ${df.format(_toDate)}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            Icon(Icons.edit, size: 14, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        _buildStatChip(
          icon: Iconsax.clipboard_text,
          value: _totalCount.toString(),
          iconColor: const Color(0xFF3F51B5),
          iconBgColor: const Color(0xFFE8EAF6),
          label: 'Total',
          // value: _totalCount.toString(),
        ),
        const SizedBox(width: 6),
        _buildStatChip(
          icon: Iconsax.clock,
          iconColor: const Color(0xFFFFA000),
          iconBgColor: const Color(0xFFFFF8E1),
          label: 'Pending',
          value: _countByStatus('Pending').toString(),
        ),
        const SizedBox(width: 6),
        _buildStatChip(
          icon: Iconsax.tick_circle,
          iconColor: const Color(0xFF4CAF50),
          iconBgColor: const Color(0xFFE8F5E9),
          label: 'Approved',
          value: _countByStatus('Approved').toString(),
        ),
        const SizedBox(width: 6),
        _buildStatChip(
          icon: Iconsax.close_circle,
          iconColor: const Color(0xFFE53935),
          iconBgColor: const Color(0xFFFFEBEE),
          label: 'Rejected',
          value: _countByStatus('Rejected').toString(),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildStatChip({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, color: iconColor, size: 14),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusFilterChips() {
    const filters = ['All', 'Pending', 'Approved', 'Rejected'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final isSelected = _statusFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _statusFilter = filter),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF031633) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF031633)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  filter,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFE8EAF6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Iconsax.clipboard_text,
                size: 44,
                color: Color(0xFF3F51B5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'No regularization requests',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage != null
                  ? 'Pull down to retry.'
                  : 'Requests you submit will show up here.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(RegularizationRequest request, int index) {
    final isExpanded = _expandedIndices.contains(index);

    Color statusColor;
    Color statusBg;
    switch (request.status.toLowerCase()) {
      case 'approved':
        statusColor = const Color(0xFF2E7D32);
        statusBg = const Color(0xFFE8F5E9);
        break;
      case 'rejected':
        statusColor = const Color(0xFFC62828);
        statusBg = const Color(0xFFFFEBEE);
        break;
      case 'pending':
      default:
        statusColor = const Color(0xFFE65100);
        statusBg = const Color(0xFFFFF3E0);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedIndices.remove(index);
                } else {
                  _expandedIndices.add(index);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.displayDate,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          request.reasonType.isNotEmpty
                              ? request.reasonType
                              : '—',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      request.status,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.grey,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 16),
                  _detailRow('Requested Times', request.requestedTimesDisplay),
                  _detailRow(
                    'Original Status',
                    request.originalStatus.isNotEmpty
                        ? request.originalStatus
                        : '—',
                  ),
                  if (request.comments.isNotEmpty)
                    _detailRow('Comments', request.comments),
                  if (request.appliedOn.isNotEmpty)
                    _detailRow('Applied On', request.displayAppliedOn),
                ],
              ),
            ),
        ],
      ),
    ).animate().fadeIn(
      delay: Duration(milliseconds: 60 * index),
      duration: 300.ms,
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
