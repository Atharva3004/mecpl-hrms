// Pre-Recruitment — list of interviewed/selected candidates, with a tap-to-open
// animated popup showing the candidate's details. Most details are read-only;
// only UAN No., ESIC No., Remarks and the photo are editable.
//
// NOTE: This screen currently runs on in-memory MOCK data (see `_candidates`).
// There is no `/api` endpoint for pre-recruitment candidates yet; once the
// backend exposes one, swap the mock list for an ApiService call and wire
// `_CandidateFormDialog`'s Submit to a POST.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

/// Places a phone call to [number] via the system dialer.
Future<void> _dial(BuildContext context, String number) async {
  final uri = Uri(scheme: 'tel', path: number.replaceAll(RegExp(r'\s'), ''));
  try {
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not place call to $number')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not place call to $number')),
      );
    }
  }
}

/// One pre-recruitment candidate. Mirrors the columns in the web admin table
/// plus the extra joining fields captured in the popup (UAN/ESIC/photo).
class PreRecruitCandidate {
  final int? id;
  final String name;
  final String email;
  final String mobile;
  final String designation;
  final String department;
  final DateTime? dob;
  final String gender;
  final String source;
  final String employeeStatus;
  final DateTime? interviewDate;
  final String interviewTime;
  bool interviewEmailSent;
  final String interviewStatus; // e.g. 'Selected'
  final DateTime? dateOfJoining;
  // Editable fields
  String remarks;
  String pf; // 'Yes' / 'No' — PF applicable (gates the UAN No. field)
  String uanNo;
  String esi; // 'Yes' / 'No' — ESI applicable (gates the ESIC No. field)
  String esicNo;
  String? photoPath; // local file path of a freshly captured photo
  String? photoUrl; // remote URL of an already-saved photo (from emp_image)

  PreRecruitCandidate({
    this.id,
    required this.name,
    required this.email,
    required this.mobile,
    required this.designation,
    required this.department,
    this.dob,
    this.gender = 'Male',
    this.source = 'Referral',
    this.employeeStatus = 'To Join',
    this.interviewDate,
    this.interviewTime = '',
    this.interviewEmailSent = true,
    this.interviewStatus = 'Selected',
    this.dateOfJoining,
    this.remarks = '',
    this.pf = '',
    this.uanNo = '',
    this.esi = '',
    this.esicNo = '',
    this.photoPath,
    this.photoUrl,
  });

  /// Builds a candidate from one element of the `/pre-recruitment/candidates`
  /// API `data` array. Tolerant of nulls — the backend returns null for
  /// unset fields (uan_no, esi_no, remarks, emp_image, …).
  factory PreRecruitCandidate.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => v?.toString().trim() ?? '';
    DateTime? d(dynamic v) {
      final str = v?.toString();
      if (str == null || str.isEmpty) return null;
      return DateTime.tryParse(str);
    }

    // Resolve emp_image into a full URL. Full URLs are used as-is; a relative
    // path (e.g. "storage/emp_images/x.jpg") is prefixed with the host root.
    String? resolveImage(dynamic v) {
      final raw = s(v);
      if (raw.isEmpty) return null;
      if (raw.startsWith('http')) return raw;
      final path = raw.startsWith('/') ? raw : '/$raw';
      return '${ApiConstants.fileBaseUrl}$path';
    }

    final gender = s(json['gender']);
    final source = s(json['sou_candidate']);
    final status = s(json['prerecruit_status']);

    return PreRecruitCandidate(
      id: json['id'] is int ? json['id'] as int : int.tryParse(s(json['id'])),
      name: s(json['emp_name']),
      email: s(json['email']),
      mobile: s(json['mobile_no']),
      designation: s(json['designation']),
      department: s(json['department']),
      dob: d(json['dob']),
      gender: gender.isEmpty ? 'Male' : gender,
      source: source.isEmpty ? 'Referral' : source,
      interviewDate: d(json['doi']),
      dateOfJoining: d(json['doj']),
      interviewStatus: status.isEmpty ? 'Selected' : status,
      remarks: s(json['remarks']),
      // `pf` / `esi` are 'Yes'/'No' flags; the numbers live in uan_no / esi_no.
      pf: s(json['pf']),
      uanNo: s(json['uan_no']),
      esi: s(json['esi']),
      esicNo: s(json['esi_no']),
      photoUrl: resolveImage(json['emp_image']),
    );
  }
}

class PreRecruitmentScreen extends StatefulWidget {
  const PreRecruitmentScreen({super.key});

  @override
  State<PreRecruitmentScreen> createState() => _PreRecruitmentScreenState();
}

class _PreRecruitmentScreenState extends State<PreRecruitmentScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  // Candidates fetched from `/pre-recruitment/candidates`.
  List<PreRecruitCandidate> _candidates = [];
  bool _isLoading = true;
  String? _errorMessage;

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

      final response = await ApiService.getPreRecruitmentCandidates(token);

      if (!mounted) return;
      if (response.isSuccess && response.data != null) {
        final raw = response.data!['data'];
        final List<PreRecruitCandidate> candidates = (raw is List)
            ? raw
                  .whereType<Map<String, dynamic>>()
                  .map(PreRecruitCandidate.fromJson)
                  .toList()
            : <PreRecruitCandidate>[];
        setState(() {
          _candidates = candidates;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = response.error ?? 'Failed to load candidates';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: $e';
      });
    }
  }

  List<PreRecruitCandidate> get _filtered {
    if (_query.isEmpty) return _candidates;
    final q = _query.toLowerCase();
    return _candidates
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.email.toLowerCase().contains(q) ||
              c.designation.toLowerCase().contains(q) ||
              c.mobile.contains(q),
        )
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openCandidate(PreRecruitCandidate candidate) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not authenticated. Please log in again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final saved = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Candidate Details',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) =>
          _CandidateFormDialog(candidate: candidate, token: token),
      transitionBuilder: (_, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Candidate details saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Pull fresh server state so the list reflects the saved details.
      _loadFromApi();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final list = _filtered;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Pre-Recruitment',
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: AppTextStyles.bodySmall,
              decoration: InputDecoration(
                hintText: 'Search by name, email, designation…',
                hintStyle: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
                prefixIcon: const Icon(Iconsax.search_normal, size: 16),
                isDense: true,
                filled: true,
                fillColor: isDark ? AppColors.darkSurface : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.border,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.border,
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody(list, isDark)),
        ],
      ),
    );
  }

  Widget _buildBody(List<PreRecruitCandidate> list, bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Iconsax.warning_2, size: 40, color: AppColors.warning),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadFromApi,
                icon: const Icon(Iconsax.refresh, size: 16),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFromApi,
      child: list.isEmpty
          ? ListView(
              // ListView (not Center) so pull-to-refresh works on the empty state.
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: Center(
                    child: Text(
                      'No candidates found',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _buildCandidateCard(list[index], index, isDark),
            ),
    );
  }

  // Compact card. Layout:
  //   [#]  NAME                              [Selected]
  //        ENGINEER · Q.A          Joining: 15-06-2026
  //        📞 9665870521        Interview: 08-06-2026
  Widget _buildCandidateCard(PreRecruitCandidate c, int index, bool isDark) {
    final muted = AppTextStyles.labelSmall.copyWith(
      fontSize: 11,
      color: isDark ? Colors.white60 : AppColors.textSecondary,
    );

    return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openCandidate(c),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Sr.No + name + status
                    Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: AppTextStyles.labelSmall.copyWith(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            c.name,
                            style: AppTextStyles.titleSmall.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _statusChip(c.interviewStatus, AppColors.success),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Two-column compact details
                    Padding(
                      padding: const EdgeInsets.only(left: 32),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left column: designation + department
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.designation,
                                  style: muted,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  c.department,
                                  style: muted,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // Right column: joining + mobile (with call icon)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DOJ: ${_fmt(c.dateOfJoining)}',
                                  style: muted,
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    InkWell(
                                      onTap: () => _dial(context, c.mobile),
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: AppColors.success.withOpacity(
                                            0.12,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Iconsax.call,
                                          size: 13,
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        c.mobile,
                                        style: muted,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
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
            ),
          ),
        )
        .animate(delay: (index * 40).ms)
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.05, end: 0, duration: 250.ms);
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static String _fmt(DateTime? d) =>
      d == null ? '—' : DateFormat('dd-MM-yyyy').format(d);
}

// ---------------------------------------------------------------------------
// Candidate popup. Details are READ-ONLY; only UAN No., ESIC No., Remarks and
// the photo are editable. Small fonts throughout.
// ---------------------------------------------------------------------------

class _CandidateFormDialog extends StatefulWidget {
  final PreRecruitCandidate candidate;
  final String token;
  const _CandidateFormDialog({required this.candidate, required this.token});

  @override
  State<_CandidateFormDialog> createState() => _CandidateFormDialogState();
}

class _CandidateFormDialogState extends State<_CandidateFormDialog> {
  late final TextEditingController _remarks;
  late final TextEditingController _uan;
  late final TextEditingController _esic;
  // Yes/No gate for the UAN/ESIC fields: the text field is only shown when the
  // toggle is Yes. Defaults to Yes when the candidate already has a value.
  bool _hasUan = false;
  bool _hasEsic = false;
  bool _submitting = false;
  String? _photoPath; // newly captured local file (takes precedence)
  String? _photoUrl; // already-saved remote photo

  @override
  void initState() {
    super.initState();
    final c = widget.candidate;
    _remarks = TextEditingController(text: c.remarks);
    _uan = TextEditingController(text: c.uanNo);
    _esic = TextEditingController(text: c.esicNo);
    // Toggle defaults to Yes when the PF/ESI flag is 'Yes' (or a number exists).
    _hasUan = c.pf.toLowerCase() == 'yes' || c.uanNo.isNotEmpty;
    _hasEsic = c.esi.toLowerCase() == 'yes' || c.esicNo.isNotEmpty;
    _photoPath = c.photoPath;
    _photoUrl = c.photoUrl;
  }

  @override
  void dispose() {
    _remarks.dispose();
    _uan.dispose();
    _esic.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    try {
      final picker = ImagePicker();
      final XFile? shot = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1080,
        maxHeight: 1080,
        preferredCameraDevice: CameraDevice.front,
      );
      if (shot != null) {
        setState(() => _photoPath = shot.path);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open camera: $e')));
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final c = widget.candidate;

    if (c.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing candidate id — cannot submit.')),
      );
      return;
    }

    // Mirror the form into the local model.
    c.remarks = _remarks.text.trim();
    c.pf = _hasUan ? 'Yes' : 'No';
    c.uanNo = _hasUan ? _uan.text.trim() : '';
    c.esi = _hasEsic ? 'Yes' : 'No';
    c.esicNo = _hasEsic ? _esic.text.trim() : '';
    c.photoPath = _photoPath;

    setState(() => _submitting = true);

    final response = await ApiService.submitPreRecruitmentDetails(
      token: widget.token,
      id: c.id.toString(),
      photoPath: _photoPath,
      pf: c.pf,
      uanNo: c.uanNo,
      esi: c.esi,
      esiNo: c.esicNo,
      remarks: c.remarks,
    );

    if (!mounted) return;
    if (response.isSuccess) {
      Navigator.pop(context, true);
    } else {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response.error ?? 'Failed to submit details')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = widget.candidate;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
              child: Row(
                children: [
                  Text(
                    'Candidate Details',
                    style: AppTextStyles.titleSmall.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    iconSize: 20,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, false),
                    color: isDark ? Colors.white70 : AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: _buildPhotoPicker(isDark)),
                    const SizedBox(height: 16),
                    // ---- Read-only details ----
                    _roRow('Emp Name', c.name, isDark),
                    _roRow('Email ID', c.email, isDark, fit: true),
                    _roMobileRow(c.mobile, isDark),
                    _roRow('Date of Birth', _fmt(c.dob), isDark),
                    _roRow('Gender', c.gender, isDark),
                    _roRow('Designation', c.designation, isDark),
                    _roRow('Department', c.department, isDark),
                    _roRow('Source of Candidate', c.source, isDark),
                    _roRow('Employee Status', c.employeeStatus, isDark),
                    _roRow('Date of Interview', _fmt(c.interviewDate), isDark),
                    _roRow('Interview Time', c.interviewTime, isDark),
                    const SizedBox(height: 12),
                    Divider(color: isDark ? Colors.white12 : Colors.black12),
                    const SizedBox(height: 8),
                    Text(
                      'Statutory Details',
                      style: AppTextStyles.labelSmall.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ---- Editable fields ----
                    _gatedEditField(
                      'UAN No.',
                      _uan,
                      _hasUan,
                      isDark,
                      keyboard: TextInputType.number,
                      onChanged: (yes) => setState(() {
                        _hasUan = yes;
                        if (!yes) _uan.clear();
                      }),
                    ),
                    _gatedEditField(
                      'ESIC No.',
                      _esic,
                      _hasEsic,
                      isDark,
                      keyboard: TextInputType.number,
                      onChanged: (yes) => setState(() {
                        _hasEsic = yes;
                        if (!yes) _esic.clear();
                      }),
                    ),
                    _editField('Remarks', _remarks, maxLines: 3),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context, false),
                    child: Text(
                      'Close',
                      style: AppTextStyles.labelMedium.copyWith(fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            'Submit',
                            style: AppTextStyles.labelMedium.copyWith(
                              fontSize: 12.5,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPicker(bool isDark) {
    // A freshly captured local file wins; otherwise fall back to the saved
    // remote photo. Only show the "Add Photo" placeholder when neither exists.
    final ImageProvider? photo = _photoPath != null
        ? FileImage(File(_photoPath!))
        : (_photoUrl != null ? NetworkImage(_photoUrl!) : null);
    final bool hasPhoto = photo != null;

    return Column(
      children: [
        GestureDetector(
          onTap: _capturePhoto,
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? AppColors.darkBackground : AppColors.background,
              border: Border.all(
                color: AppColors.primary.withOpacity(0.4),
                width: 2,
              ),
              image: hasPhoto
                  ? DecorationImage(image: photo, fit: BoxFit.cover)
                  : null,
            ),
            child: hasPhoto
                ? null
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Iconsax.camera,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Add Photo',
                        style: AppTextStyles.labelSmall.copyWith(
                          fontSize: 10,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (hasPhoto)
          TextButton.icon(
            onPressed: _capturePhoto,
            icon: const Icon(Iconsax.camera, size: 14),
            label: Text(
              'Retake',
              style: AppTextStyles.labelSmall.copyWith(fontSize: 11),
            ),
          ),
      ],
    );
  }

  // Read-only label/value row, small font. When [fit] is true the value is
  // kept on a single line and scaled down to fit the available width (used for
  // the long email address so it doesn't wrap).
  Widget _roRow(String label, String value, bool isDark, {bool fit = false}) {
    final valueText = Text(
      value.isEmpty ? '—' : value,
      maxLines: fit ? 1 : null,
      softWrap: !fit,
      style: AppTextStyles.bodySmall.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.white : AppColors.textPrimary,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                fontSize: 11,
                color: isDark ? Colors.white54 : AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: fit
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: valueText,
                    ),
                  )
                : valueText,
          ),
        ],
      ),
    );
  }

  // Mobile row with a tap-to-call icon before the number.
  Widget _roMobileRow(String mobile, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: 116,
            child: Text(
              'Mobile Number',
              style: AppTextStyles.labelSmall.copyWith(
                fontSize: 11,
                color: isDark ? Colors.white54 : AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: () => _dial(context, mobile),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Iconsax.call,
                size: 18,
                color: AppColors.success,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mobile.isEmpty ? '—' : mobile,
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Label + Yes/No toggle. The editable text field is only shown when [selected]
  // is true. Tapping No clears the value (handled by the caller's onChanged).
  Widget _gatedEditField(
    String label,
    TextEditingController controller,
    bool selected,
    bool isDark, {
    TextInputType? keyboard,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.labelSmall.copyWith(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : AppColors.textSecondary,
                  ),
                ),
              ),
              _yesNoToggle(selected, onChanged, isDark),
            ],
          ),
          if (selected) ...[
            const SizedBox(height: 10),
            _editField(label, controller, keyboard: keyboard),
          ],
        ],
      ),
    );
  }

  // Trendy animated Yes/No slider toggle. A pill-shaped track with a sliding
  // thumb that snaps to the active side; the track tints green for Yes and a
  // muted grey for No.
  Widget _yesNoToggle(
    bool selected,
    ValueChanged<bool> onChanged,
    bool isDark,
  ) {
    const double w = 88;
    const double h = 30;
    const double pad = 3;
    const double thumbW = (w - pad * 2) / 2;

    final Color trackColor = selected
        ? AppColors.success.withOpacity(0.18)
        : (isDark ? Colors.white12 : Colors.black12);
    final Color thumbColor = selected
        ? AppColors.success
        : Colors.grey.shade500;

    Widget sideLabel(String text, bool active) {
      return Expanded(
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: AppTextStyles.labelSmall.copyWith(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active
                  ? Colors.white
                  : (isDark ? Colors.white60 : AppColors.textSecondary),
            ),
            child: Text(text),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => onChanged(!selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: w,
        height: h,
        padding: const EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(h / 2),
        ),
        child: Stack(
          children: [
            // Sliding thumb
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: selected
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Container(
                width: thumbW,
                height: h - pad * 2,
                decoration: BoxDecoration(
                  color: thumbColor,
                  borderRadius: BorderRadius.circular(h / 2),
                  boxShadow: [
                    BoxShadow(
                      color: thumbColor.withOpacity(0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            // Labels above the thumb
            Row(
              children: [
                sideLabel('Yes', selected),
                sideLabel('No', !selected),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Editable text field, small font.
  Widget _editField(
    String label,
    TextEditingController controller, {
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: AppTextStyles.bodySmall.copyWith(fontSize: 12.5),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppTextStyles.labelSmall.copyWith(fontSize: 12),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 11,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  static String _fmt(DateTime? d) =>
      d == null ? '' : DateFormat('dd-MM-yyyy').format(d);
}
