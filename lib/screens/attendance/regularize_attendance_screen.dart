import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common/custom_loader.dart';

class RegularizeAttendanceScreen extends StatefulWidget {
  final Map<String, dynamic> attendanceRecord;

  const RegularizeAttendanceScreen({super.key, required this.attendanceRecord});

  @override
  State<RegularizeAttendanceScreen> createState() =>
      _RegularizeAttendanceScreenState();
}

class _RegularizeAttendanceScreenState extends State<RegularizeAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blinkController;
  DateTime? _modifiedInDate;
  TimeOfDay? _modifiedInTime;
  DateTime? _modifiedOutDate;
  TimeOfDay? _modifiedOutTime;
  TimeOfDay? _shiftStartTime;
  TimeOfDay? _shiftEndTime;
  TimeOfDay? _actualInTime;
  TimeOfDay? _actualOutTime;
  // Currently selected preset (single-select radio group):
  // 'full' | 'firstHalfIn' | 'secondHalfIn' | 'firstHalfOut' | 'secondHalfOut'
  String? _selectedPreset;
  String? _selectedReasonType;
  final TextEditingController _commentsController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLoadingData = true;

  DateTime? _recordDate;
  String? _dailyAttendanceId;
  String _shiftName = '--';
  String _shiftInTime = '--:--';
  String _shiftOutTime = '--:--';
  String _actualInTimeVal = 'NA';
  String _actualOutTimeVal = 'NA';

  final List<String> _reasonTypes = [
    'Forgot to Punch',
    'On Duty',
    'Work From Home',
    'Client Visit',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _recordDate = _parseRecordDate();
    _modifiedInDate = _recordDate;
    _modifiedOutDate = _recordDate;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _fetchRegularizationData(),
    );
  }

  DateTime _parseRecordDate() {
    final dateStr = (widget.attendanceRecord['date'] ?? '').toString();
    try {
      return DateFormat('dd-MM-yyyy').parse(dateStr);
    } catch (_) {
      try {
        return DateTime.parse(dateStr);
      } catch (_) {
        return DateTime.now();
      }
    }
  }

  TimeOfDay? _parseApiTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatApiTime(String? raw) {
    final t = _parseApiTime(raw);
    if (t == null) return '--:--';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _fetchRegularizationData() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || _recordDate == null) {
      if (mounted) setState(() => _isLoadingData = false);
      return;
    }

    final apiDate = DateFormat('yyyy-MM-dd').format(_recordDate!);
    final response = await ApiService.getMyRegularizationData(
      token: token,
      fromDate: apiDate,
      toDate: apiDate,
    );

    if (!mounted) return;

    if (response.isSuccess && response.data is Map) {
      final data = response.data as Map;
      final list = data['data'];
      if (list is List && list.isNotEmpty) {
        final record = list.first as Map;
        _dailyAttendanceId = record['id']?.toString();
        final firstIn = record['first_in']?.toString();
        final lastOut = record['last_out']?.toString();
        final shiftStart = record['shift_start']?.toString();
        final shiftEnd = record['shift_end']?.toString();

        setState(() {
          _shiftName = (record['shift_name']?.toString().isNotEmpty ?? false)
              ? record['shift_name'].toString()
              : '--';
          _shiftInTime = _formatApiTime(shiftStart);
          _shiftOutTime = _formatApiTime(shiftEnd);
          _shiftStartTime = _parseApiTime(shiftStart);
          _shiftEndTime = _parseApiTime(shiftEnd);
          _actualInTimeVal =
              (firstIn != null && firstIn.isNotEmpty && firstIn != 'null')
              ? firstIn
              : 'NA';
          _actualOutTimeVal =
              (lastOut != null && lastOut.isNotEmpty && lastOut != 'null')
              ? lastOut
              : 'NA';
          _actualInTime = _parseApiTime(firstIn);
          _actualOutTime = _parseApiTime(lastOut);
          _modifiedInTime = _actualInTime;
          _modifiedOutTime = _actualOutTime;
        });
      }
    }

    setState(() => _isLoadingData = false);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  String get _displayDate {
    final dateStr = (widget.attendanceRecord['date'] ?? '').toString();
    try {
      final DateFormat formatter = DateFormat('dd-MM-yyyy');
      final dateTime = formatter.parse(dateStr);
      return DateFormat('dd MMM yyyy').format(dateTime);
    } catch (_) {
      try {
        final dateTime = DateTime.parse(dateStr);
        return DateFormat('dd MMM yyyy').format(dateTime);
      } catch (_) {
        return dateStr;
      }
    }
  }

  String _formatTimeOnly(TimeOfDay? time) {
    if (time == null) return '--:--';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Lunch-break boundaries: first half ends at 13:00, second half starts at 14:00.
  static const TimeOfDay _firstHalfEndTime = TimeOfDay(hour: 13, minute: 0);
  static const TimeOfDay _secondHalfStartTime = TimeOfDay(hour: 14, minute: 0);

  // Selecting a preset is single-select: picking one clears any other.
  void _applyPreset(String key) {
    setState(() {
      if (_selectedPreset == key) {
        // Tapping the active preset again clears it.
        _selectedPreset = null;
        return;
      }
      _selectedPreset = key;
      switch (key) {
        case 'full':
          // Full shift regularizes both sides.
          _modifiedInTime = _shiftStartTime;
          _modifiedOutTime = _shiftEndTime;
          break;
        case 'firstHalfIn':
          // Only IN changes; OUT keeps the actual punched time.
          _modifiedInTime = _shiftStartTime;
          _modifiedOutTime = _actualOutTime;
          break;
        case 'secondHalfIn':
          // Only IN changes; OUT keeps the actual punched time.
          _modifiedInTime = _secondHalfStartTime;
          _modifiedOutTime = _actualOutTime;
          break;
        case 'firstHalfOut':
          // Only OUT changes; IN keeps the actual punched time.
          _modifiedInTime = _actualInTime;
          _modifiedOutTime = _firstHalfEndTime;
          break;
        case 'secondHalfOut':
          // Only OUT changes; IN keeps the actual punched time.
          _modifiedInTime = _actualInTime;
          _modifiedOutTime = _shiftEndTime;
          break;
      }
    });
  }

  void _clearPresetSelection() {
    setState(() => _selectedPreset = null);
  }

  // Full Shift needs a confirmation because it is only meant for
  // outdoor work / emergency duty. OK selects it, Cancel leaves it unselected.
  Future<void> _onTapFullShift() async {
    // Tapping the already-selected card just clears it, no warning needed.
    if (_selectedPreset == 'full') {
      _applyPreset('full');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFFDB940),
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              'Warning',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        content: Text(
          'Only Applicable for outdoor work and Emergency duty',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.black87,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF031633),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'OK',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _applyPreset('full');
    }
  }

  String get _presetSummary {
    if (_selectedPreset == null) {
      return 'Select a preset to see what will be regularized.';
    }
    final actualIn = _formatTimeOnly(_actualInTime);
    final actualOut = _formatTimeOnly(_actualOutTime);
    final modIn = _formatTimeOnly(_modifiedInTime);
    final modOut = _formatTimeOnly(_modifiedOutTime);
    switch (_selectedPreset) {
      case 'firstHalfIn':
      case 'secondHalfIn':
        // Regularizing the IN side.
        return 'Your actual IN time is $actualIn and your regularizing IN time as $modIn';
      case 'firstHalfOut':
      case 'secondHalfOut':
        // Regularizing the OUT side.
        return 'Your actual OUT time is $actualOut and your regularizing OUT time as $modOut';
      default:
        return 'Your actual IN/OUT time is $actualIn / $actualOut and your regularizing IN/OUT time as $modIn / $modOut';
    }
  }

  Future<void> _handleSubmit() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (_dailyAttendanceId == null) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Attendance record not loaded yet'),
          backgroundColor: const Color(0xFFC62828),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    if (_modifiedInTime == null || _modifiedOutTime == null) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Please set both modified in and out times'),
          backgroundColor: const Color(0xFFC62828),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final modInTime = _formatTimeOnly(_modifiedInTime);
    final modOutTime = _formatTimeOnly(_modifiedOutTime);

    final reasonParts = <String>[
      if ((_selectedReasonType ?? '').isNotEmpty) _selectedReasonType!,
      if (_commentsController.text.trim().isNotEmpty)
        _commentsController.text.trim(),
    ];
    final reason = reasonParts.join(' - ');

    final provider = context.read<AttendanceProvider>();

    final success = await provider.submitRegularization(
      token: token,
      dailyAttendanceId: _dailyAttendanceId!,
      newInTime: modInTime,
      newOutTime: modOutTime,
      reason: reason,
    );

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (success) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Regularization submitted successfully'),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      navigator.pop(true);
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Failed to submit'),
          backgroundColor: const Color(0xFFC62828),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

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
          "Regularize Attendance",
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      body: _isLoadingData
          ? const Center(child: CustomLoader(size: 60))
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),

                        // Date
                        Text(
                          _displayDate,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Shift
                        Text(
                          'SHIFT',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _shiftName,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Actual In/Out Times
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoField(
                                'ACTUAL IN TIME',
                                _actualInTimeVal,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildInfoField(
                                'ACTUAL OUT TIME',
                                _actualOutTimeVal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Shift In/Out Times
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoField(
                                'SHIFT IN TIME',
                                _shiftInTime,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildInfoField(
                                'SHIFT OUT TIME',
                                _shiftOutTime,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Modified In/Out Times (editable)
                        Row(
                          children: [
                            Expanded(
                              child: _buildModifiedTimeField(
                                'MODIFIED IN TIME',
                                _modifiedInDate,
                                _modifiedInTime,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildModifiedTimeField(
                                'MODIFIED OUT TIME',
                                _modifiedOutDate,
                                _modifiedOutTime,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ---- Regularization presets (single-select) ----
                        // Modified In — pick a half
                        _buildPresetSectionLabel('MODIFIED IN — PICK A HALF'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildPresetChip(
                                key: 'firstHalfIn',
                                title: '1st Half In',
                                time: _shiftStartTime,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildPresetChip(
                                key: 'secondHalfIn',
                                title: '2nd Half IN',
                                time: _secondHalfStartTime,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Modified Out — pick a half
                        _buildPresetSectionLabel('MODIFIED OUT — PICK A HALF'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildPresetChip(
                                key: 'firstHalfOut',
                                title: '1st Half Out',
                                time: _firstHalfEndTime,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildPresetChip(
                                key: 'secondHalfOut',
                                title: '2nd Half Out',
                                time: _shiftEndTime,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Full Shift
                        _buildFullShiftCard(),
                        const SizedBox(height: 4),

                        // Clear selection
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _selectedPreset == null
                                ? null
                                : _clearPresetSelection,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Clear selection',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                color: _selectedPreset == null
                                    ? Colors.grey.shade400
                                    : const Color(0xFF031633),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Summary hint
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: FadeTransition(
                            opacity: Tween<double>(
                              begin: 0.25,
                              end: 1.0,
                            ).animate(_blinkController),
                            child: Text(
                              _presetSummary,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: const Color(0xFFD32F2F),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Divider
                        Divider(color: Colors.grey.shade200),
                        const SizedBox(height: 8),

                        // Reason Type Dropdown
                        Text(
                          'REASON TYPE  (Optional)',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedReasonType,
                              hint: Text(
                                'Select',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.black87,
                                ),
                              ),
                              isExpanded: true,
                              icon: Icon(
                                Icons.keyboard_arrow_down,
                                color: Colors.grey.shade500,
                              ),
                              items: _reasonTypes.map((type) {
                                return DropdownMenuItem(
                                  value: type,
                                  child: Text(
                                    type,
                                    style: GoogleFonts.poppins(fontSize: 12),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() => _selectedReasonType = val);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Comments
                        Text(
                          'COMMENTS  (Optional)',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Stack(
                            children: [
                              TextField(
                                controller: _commentsController,
                                maxLines: 4,
                                maxLength: 150,
                                onChanged: (_) => setState(() {}),
                                style: GoogleFonts.poppins(fontSize: 12),
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.all(12),
                                  border: InputBorder.none,
                                  counterText: '',
                                  hintText: '',
                                  hintStyle: GoogleFonts.poppins(
                                    color: Colors.grey.shade400,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 8,
                                bottom: 4,
                                child: Text(
                                  '${_commentsController.text.length}/150',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),

                // Submit Button
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  color: Colors.white,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF031633),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(
                        0xFF031633,
                      ).withOpacity(0.6),
                      disabledForegroundColor: Colors.white70,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Submit',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
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

  Widget _buildPresetSectionLabel(String text) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFFFDB940),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildFullShiftCard() {
    final selected = _selectedPreset == 'full';
    final range =
        '${_formatTimeOnly(_shiftStartTime)} → ${_formatTimeOnly(_shiftEndTime)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPresetSectionLabel('FULL SHIFT'),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _onTapFullShift,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? const Color(0xFFFDB940)
                    : Colors.grey.shade300,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                _buildRadioDot(selected),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.poppins(color: Colors.black87),
                      children: [
                        TextSpan(
                          text: 'In & Out',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        TextSpan(
                          text: '  ·  $range',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChip({
    required String key,
    required String title,
    required TimeOfDay? time,
  }) {
    final selected = _selectedPreset == key;
    return GestureDetector(
      onTap: () => _applyPreset(key),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7E8) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFFFDB940) : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            _buildRadioDot(selected),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _formatTimeOnly(time),
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF031633),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioDot(bool selected) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFFFDB940) : Colors.grey.shade400,
          width: 1.5,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFFDB940),
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildModifiedTimeField(
    String label,
    DateTime? date,
    TimeOfDay? time,
  ) {
    final displayText = date != null && time != null
        ? '${DateFormat('dd MMM yyyy').format(date)}\n${_formatTimeOnly(time)}'
        : '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFFDB940),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                displayText,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.access_time,
                size: 18,
                color: Color(0xFFFDB940),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
