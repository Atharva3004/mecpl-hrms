// Resignation submission screen.
//
// Layout matches the web version (red section bars, compact field rows, tight
// font sizes). Backend wiring is stubbed for now — `_submit()` logs the payload
// and shows a success dialog. To wire to a real API, replace the stub with an
// ApiService call.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';

/// SharedPreferences key for the persisted resignation submission. Cleared by
/// "Withdraw Resignation" or wiped externally on logout if HR ever wants that.
const String _kResignationPref = 'resignation_submission_v1';

/// Hard cap per attached file. Files larger than this are rejected with a
/// snackbar — keeps the persisted-on-device copy small enough that prefs +
/// app docs dir don't bloat over time.
const int _kMaxAttachmentBytes = 2 * 1024 * 1024;

/// Lightweight snapshot of a file the user attached. We copy the picked file
/// into the app's documents directory so the submitted-state view can reopen
/// it later even if the original source is gone (e.g. a screenshot the user
/// deleted from gallery after picking).
class _Attachment {
  final String name;
  final String path;
  final int sizeBytes;

  const _Attachment({
    required this.name,
    required this.path,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'size_bytes': sizeBytes,
  };

  factory _Attachment.fromJson(Map<String, dynamic> j) => _Attachment(
    name: j['name']?.toString() ?? 'attachment',
    path: j['path']?.toString() ?? '',
    sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
  );
}

/// Pretty-prints a byte count as KB / MB. Used in attachment chips.
String _fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

class ResignationScreen extends StatefulWidget {
  const ResignationScreen({super.key});

  @override
  State<ResignationScreen> createState() => _ResignationScreenState();
}

class _ResignationScreenState extends State<ResignationScreen> {
  static const _bandHeader = Color(0xFFE85C5C); // red bar (matches mockup)
  static const _smallLabel = 11.0;
  static const _smallValue = 13.0;
  static const _sectionGap = 12.0;

  late final DateTime _today;
  DateTime? _expectedRelievingDate;
  bool? _readyToServeNotice; // null = not picked yet, true/false thereafter
  String? _notServingReason;
  bool _declared = false;
  bool _isSubmitting = false;
  bool _isWithdrawing = false;

  /// True until we've finished the initial SharedPreferences read so we can
  /// decide whether to show the form or the submitted-state view. Without
  /// this flag the form would flash for one frame on screens with an
  /// existing submission.
  bool _isLoadingState = true;

  /// Holds the persisted submission payload when one exists. `null` means
  /// the user hasn't submitted (or has just withdrawn), so the form is shown.
  Map<String, dynamic>? _submitted;

  final TextEditingController _reasonCtrl = TextEditingController();

  /// Files the user has attached on the current (unsubmitted) form. Each
  /// entry has already been copied into the app's documents directory so
  /// the path is stable across the user's interactions with the picker.
  final List<_Attachment> _attachments = [];
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    // Default expected relieving date = today + 30 days (typical notice period).
    _expectedRelievingDate = _today.add(const Duration(days: 30));
    _loadPersistedSubmission();
  }

  Future<void> _loadPersistedSubmission() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kResignationPref);
    if (!mounted) return;
    if (raw == null || raw.isEmpty) {
      setState(() => _isLoadingState = false);
      return;
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _submitted = data;
        _isLoadingState = false;
      });
    } catch (_) {
      // Corrupted blob — wipe it so the form shows.
      await prefs.remove(_kResignationPref);
      if (!mounted) return;
      setState(() => _isLoadingState = false);
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  // ---- Attachments --------------------------------------------------------

  /// Opens the system file picker (any MIME type, multi-select), enforces the
  /// 2 MB per-file cap, copies survivors into the app's documents directory,
  /// and appends them to [_attachments].
  Future<void> _pickAttachments() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      final docsDir = await getApplicationDocumentsDirectory();
      final destDir = Directory('${docsDir.path}/resignation_attachments');
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      final accepted = <_Attachment>[];
      final rejected = <String>[];

      for (final f in result.files) {
        final src = f.path;
        if (src == null) continue;
        if (f.size > _kMaxAttachmentBytes) {
          rejected.add(f.name);
          continue;
        }
        // Prefix with microsecond timestamp so two picks of the same filename
        // don't clobber each other.
        final stamp = DateTime.now().microsecondsSinceEpoch;
        final destPath = '${destDir.path}/${stamp}_${f.name}';
        await File(src).copy(destPath);
        accepted.add(
          _Attachment(name: f.name, path: destPath, sizeBytes: f.size),
        );
      }

      if (!mounted) return;
      if (accepted.isNotEmpty) {
        setState(() => _attachments.addAll(accepted));
      }
      if (rejected.isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                rejected.length == 1
                    ? '"${rejected.first}" is larger than 2 MB and was skipped.'
                    : '${rejected.length} files were larger than 2 MB and were skipped.',
              ),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not attach file: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _removeAttachment(_Attachment a) async {
    setState(() => _attachments.remove(a));
    // Best-effort cleanup of the cached copy.
    try {
      final f = File(a.path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> _openAttachment(_Attachment a) async {
    final result = await OpenFile.open(a.path);
    if (!mounted) return;
    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  // ---- Submission ---------------------------------------------------------

  // Submit becomes tappable as soon as the declaration is ticked. We don't
  // gate it on the other fields — the user explicitly wants checkbox →
  // button visible → tap → submit, no extra blockers. Validation can be
  // added later if HR needs required fields enforced.
  bool get _canSubmit => _declared && !_isSubmitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);

    // STUB — replace with ApiService.submitResignation(...) when the backend
    // endpoint is ready. Payload structure here is what we'll POST:
    final payload = <String, dynamic>{
      'date_of_resignation': DateFormat('yyyy-MM-dd').format(_today),
      'expected_relieving_date': DateFormat(
        'yyyy-MM-dd',
      ).format(_expectedRelievingDate!),
      'reason_for_leaving': _reasonCtrl.text.trim(),
      'ready_to_serve_notice': _readyToServeNotice,
      'not_serving_reason': _notServingReason, // null if readyToServe=true
      'declared': _declared,
      'submitted_at': DateTime.now().toIso8601String(),
      'attachments': _attachments.map((a) => a.toJson()).toList(),
    };
    debugPrint('🪪 Resignation payload: $payload');

    // Fake network latency for realism.
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    // Persist so a screen rebuild / app restart still shows the submitted
    // view. Cleared by Withdraw Resignation.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kResignationPref, jsonEncode(payload));

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _submitted = payload;
    });

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Iconsax.tick_circle, color: Colors.green, size: 48),
        title: const Text('Resignation submitted'),
        content: const Text(
          'Your resignation has been recorded. HR will reach out shortly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    // Don't pop the screen — the build will now render the submitted view
    // with a Withdraw option. User can navigate back via the AppBar arrow.
  }

  Future<void> _withdraw() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(Iconsax.warning_2, color: AppColors.warning, size: 40),
        title: const Text('Withdraw resignation?'),
        content: const Text(
          'All the details you submitted will be wiped. You can re-submit a '
          'fresh resignation later if needed.\n\n'
          'Are you sure you want to withdraw?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isWithdrawing = true);

    // Best-effort cleanup of any persisted attachment files. Pulled from the
    // submitted payload rather than the in-memory list so we still catch
    // files attached in a previous session that survived an app restart.
    final attachmentsJson = _submitted?['attachments'];
    if (attachmentsJson is List) {
      for (final raw in attachmentsJson) {
        if (raw is Map) {
          final path = raw['path']?.toString();
          if (path != null && path.isNotEmpty) {
            try {
              final f = File(path);
              if (await f.exists()) await f.delete();
            } catch (_) {}
          }
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kResignationPref);
    // Brief delay so the user sees the spinner — stops the UI from feeling
    // jarringly instant. Remove if you'd prefer no delay.
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    setState(() {
      _submitted = null;
      _isWithdrawing = false;
      // Reset all form state so the form opens fresh, not pre-populated
      // with whatever the user submitted.
      _expectedRelievingDate = _today.add(const Duration(days: 30));
      _readyToServeNotice = null;
      _notServingReason = null;
      _declared = false;
      _reasonCtrl.clear();
      _attachments.clear();
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Resignation withdrawn. You can start fresh.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ---- Notice-period popup ------------------------------------------------

  Future<void> _showNoticePeriodPopup() async {
    final ctrl = TextEditingController(text: _notServingReason ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Iconsax.warning_2, color: AppColors.warning, size: 22),
            const SizedBox(width: 8),
            const Expanded(child: Text('Notice period')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Text(
                'If you choose not to serve the notice period, you may have '
                'to pay the company in lieu as per your employment contract.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Reason for not serving notice',
              style: GoogleFonts.inter(
                fontSize: _smallLabel,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              maxLines: 3,
              maxLength: 500,
              style: GoogleFonts.inter(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Why can\'t you serve the notice period?',
                hintStyle: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            // Cancel: popup just closes, "No" stays selected (user's choice).
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      setState(() => _notServingReason = result);
    }
  }

  // ---- Date picker --------------------------------------------------------

  Future<void> _pickRelievingDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _expectedRelievingDate ?? _today.add(const Duration(days: 30)),
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 180)),
    );
    if (picked != null && mounted) {
      setState(() => _expectedRelievingDate = picked);
    }
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left_2),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Resignation',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: _isLoadingState
            ? const Center(child: CircularProgressIndicator())
            : _submitted != null
            ? _buildSubmittedView(isDark: isDark)
            : _buildFormView(isDark: isDark),
      ),
    );
  }

  // ---- Form view (used when no submission exists) -------------------------

  Widget _buildFormView({required bool isDark}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSection(
            title: 'Relieving Info',
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildReadOnlyRow(
                  label: 'DATE OF RESIGNATION',
                  value: DateFormat('dd MMM yyyy').format(_today),
                  isDark: isDark,
                ),
                const SizedBox(height: _sectionGap),
                _buildDateRow(
                  label: 'EXPECTED RELIEVING DATE',
                  date: _expectedRelievingDate,
                  onTap: _pickRelievingDate,
                  isDark: isDark,
                ),
                const SizedBox(height: _sectionGap),
                _buildAttachmentField(isDark: isDark),
                const SizedBox(height: _sectionGap),
                _buildReasonField(isDark: isDark),
              ],
            ),
          ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0),

          const SizedBox(height: 14),

          _buildSection(
                title: 'Notice Period',
                isDark: isDark,
                child: _buildNoticeBlock(isDark: isDark),
              )
              .animate(delay: 80.ms)
              .fadeIn(duration: 250.ms)
              .slideY(begin: 0.04, end: 0),

          const SizedBox(height: 14),

          _buildSection(
                title: 'Declaration',
                isDark: isDark,
                child: _buildDeclarationBlock(isDark: isDark),
              )
              .animate(delay: 160.ms)
              .fadeIn(duration: 250.ms)
              .slideY(begin: 0.04, end: 0),

          const SizedBox(height: 18),

          // Submit button — only shown after the user ticks the
          // declaration checkbox. Animated in/out so it doesn't pop.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _declared
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _buildSubmitButton(),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ---- Submitted-state view (shown after submit succeeds) -----------------

  Widget _buildSubmittedView({required bool isDark}) {
    final data = _submitted!;
    final submittedAt =
        DateTime.tryParse(data['submitted_at']?.toString() ?? '') ??
        DateTime.now();
    final dateOfRes = data['date_of_resignation']?.toString() ?? '';
    final relievingDate = data['expected_relieving_date']?.toString() ?? '';
    final reason = data['reason_for_leaving']?.toString() ?? '';
    final readyToServe = data['ready_to_serve_notice'] == true;
    final notServingReason = data['not_serving_reason']?.toString();
    final attachments = <_Attachment>[
      for (final raw in (data['attachments'] as List? ?? const []))
        if (raw is Map<String, dynamic>) _Attachment.fromJson(raw),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status banner — orange "pending HR review" pill at the top.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.warning.withOpacity(0.18),
                  AppColors.warning.withOpacity(0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Iconsax.clock,
                    color: AppColors.warning,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resignation submitted',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pending HR review · ${DateFormat('dd MMM yyyy, hh:mm a').format(submittedAt)}',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0),

          const SizedBox(height: 16),

          _buildSection(
                title: 'Submitted Details',
                isDark: isDark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildReadOnlyRow(
                      label: 'DATE OF RESIGNATION',
                      value: _prettyDate(dateOfRes),
                      isDark: isDark,
                    ),
                    const SizedBox(height: _sectionGap),
                    _buildReadOnlyRow(
                      label: 'EXPECTED RELIEVING DATE',
                      value: _prettyDate(relievingDate),
                      isDark: isDark,
                    ),
                    if (attachments.isNotEmpty) ...[
                      const SizedBox(height: _sectionGap),
                      Text(
                        'ATTACHMENTS',
                        style: GoogleFonts.inter(
                          fontSize: _smallLabel,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final a in attachments)
                            _AttachmentChip(
                              attachment: a,
                              isDark: isDark,
                              onOpen: () => _openAttachment(a),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: _sectionGap),
                    _buildReadOnlyRow(
                      label: 'REASON FOR LEAVING',
                      value: reason.isEmpty ? '—' : reason,
                      isDark: isDark,
                    ),
                    const SizedBox(height: _sectionGap),
                    _buildReadOnlyRow(
                      label: 'SERVE NOTICE PERIOD',
                      value: readyToServe ? 'Yes' : 'No',
                      isDark: isDark,
                    ),
                    if (!readyToServe &&
                        notServingReason != null &&
                        notServingReason.isNotEmpty) ...[
                      const SizedBox(height: _sectionGap),
                      _buildReadOnlyRow(
                        label: 'REASON FOR NOT SERVING NOTICE',
                        value: notServingReason,
                        isDark: isDark,
                      ),
                    ],
                  ],
                ),
              )
              .animate(delay: 80.ms)
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.05, end: 0),

          const SizedBox(height: 18),

          // Withdraw button + helper text.
          Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Iconsax.refresh_circle,
                          color: AppColors.error,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Changed your mind?',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'You can withdraw your resignation. All submitted details '
                      'will be wiped and you can submit a fresh resignation later '
                      'if needed.',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _isWithdrawing ? null : _withdraw,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: BorderSide(color: AppColors.error),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: _isWithdrawing
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    AppColors.error,
                                  ),
                                ),
                              )
                            : Icon(
                                Iconsax.close_circle,
                                size: 18,
                                color: AppColors.error,
                              ),
                        label: Text(
                          _isWithdrawing
                              ? 'Withdrawing…'
                              : 'Withdraw Resignation',
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
              .animate(delay: 160.ms)
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.05, end: 0),
        ],
      ),
    );
  }

  /// Formats yyyy-MM-dd → dd MMM yyyy. Returns original string if parsing
  /// fails so the user still sees something.
  String _prettyDate(String iso) {
    if (iso.isEmpty) return '—';
    final parsed = DateTime.tryParse(iso);
    return parsed == null ? iso : DateFormat('dd MMM yyyy').format(parsed);
  }

  // ---- Section card + red header ------------------------------------------

  Widget _buildSection({
    required String title,
    required Widget child,
    required bool isDark,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: _bandHeader,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: child,
          ),
        ],
      ),
    );
  }

  // ---- Field widgets ------------------------------------------------------

  Widget _buildReadOnlyRow({
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: _smallLabel,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: _smallValue,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildDateRow({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: _smallLabel,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    date == null
                        ? 'Select date'
                        : DateFormat('dd MMM yyyy').format(date),
                    style: GoogleFonts.inter(
                      fontSize: _smallValue,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : AppColors.textPrimary,
                    ),
                  ),
                ),
                Icon(Iconsax.calendar_edit, color: AppColors.primary, size: 18),
              ],
            ),
            const SizedBox(height: 4),
            Divider(
              color: isDark ? Colors.white12 : AppColors.border,
              height: 1,
            ),
          ],
        ),
      ),
    );
  }

  /// ATTACHMENT field — paperclip "add" tile on the left, followed by chips
  /// for each picked file (filename + size + tap-to-open + × to remove).
  /// Sits above REASON FOR LEAVING per the design mockup.
  Widget _buildAttachmentField({required bool isDark}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ATTACHMENT',
          style: GoogleFonts.inter(
            fontSize: _smallLabel,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Paperclip "add" tile — always present, opens the picker.
            InkWell(
              onTap: _isPicking ? null : _pickAttachments,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white24 : AppColors.border,
                  ),
                ),
                alignment: Alignment.center,
                child: _isPicking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Iconsax.attach_square,
                        size: 22,
                        color: AppColors.textTertiary,
                      ),
              ),
            ),
            for (final a in _attachments)
              _AttachmentChip(
                attachment: a,
                isDark: isDark,
                onOpen: () => _openAttachment(a),
                onRemove: () => _removeAttachment(a),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Max 2 MB per file. Any file type.',
          style: GoogleFonts.inter(
            fontSize: 10.5,
            color: AppColors.textTertiary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildReasonField({required bool isDark}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '* ',
              style: GoogleFonts.inter(
                fontSize: _smallLabel,
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'REASON FOR LEAVING',
              style: GoogleFonts.inter(
                fontSize: _smallLabel,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _reasonCtrl,
          maxLines: 4,
          maxLength: 2900,
          inputFormatters: [LengthLimitingTextInputFormatter(2900)],
          style: GoogleFonts.inter(
            fontSize: _smallValue,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Please share why you are resigning.',
            hintStyle: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
          ),
          onChanged: (val) => setState(() {
            // If the user clears the field after ticking the declaration,
            // auto-untick so they can't bypass the rule by editing afterwards.
            if (val.trim().isEmpty && _declared) {
              _declared = false;
            }
          }),
        ),
      ],
    );
  }

  // ---- Notice Period block ------------------------------------------------

  Widget _buildNoticeBlock({required bool isDark}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '* ',
              style: GoogleFonts.inter(
                fontSize: _smallLabel,
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'SERVE NOTICE PERIOD?',
              style: GoogleFonts.inter(
                fontSize: _smallLabel,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildChoiceChip(
                label: 'Yes',
                selected: _readyToServeNotice == true,
                color: AppColors.success,
                onTap: () => setState(() {
                  _readyToServeNotice = true;
                  _notServingReason = null;
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildChoiceChip(
                label: 'No',
                selected: _readyToServeNotice == false,
                color: AppColors.error,
                onTap: () async {
                  setState(() => _readyToServeNotice = false);
                  await _showNoticePeriodPopup();
                },
              ),
            ),
          ],
        ),
        if (_readyToServeNotice == false && _notServingReason != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Iconsax.note_text, size: 14, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Text(
                      'Reason captured',
                      style: GoogleFonts.inter(
                        fontSize: _smallLabel,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: _showNoticePeriodPopup,
                      child: Text(
                        'Edit',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _notServingReason!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.transparent,
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Iconsax.tick_circle : Iconsax.record_circle,
              size: 16,
              color: selected ? color : AppColors.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Declaration block --------------------------------------------------

  Widget _buildDeclarationBlock({required bool isDark}) {
    // Checkbox is gated on the reason field having content. The reason
    // TextField's onChanged already calls setState, so this rebuilds whenever
    // the user types.
    final reasonFilled = _reasonCtrl.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: reasonFilled
              ? () => setState(() => _declared = !_declared)
              : () {
                  // Reason is empty — explain why the checkbox isn't reacting.
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Please write the reason for leaving first.',
                        ),
                        duration: const Duration(seconds: 2),
                        backgroundColor: AppColors.error,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _declared ? AppColors.primary : Colors.transparent,
                    border: Border.all(
                      color: _declared
                          ? AppColors.primary
                          : reasonFilled
                          ? AppColors.textTertiary
                          // Lighter / muted border when checkbox is
                          // effectively disabled.
                          : AppColors.border,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _declared
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '* I HEREBY DECLARE THAT I AM SUBMITTING MY RESIGNATION.',
                    style: GoogleFonts.inter(
                      fontSize: _smallLabel,
                      fontWeight: FontWeight.w600,
                      // Dim the label when disabled so the user can see it's
                      // not tappable yet.
                      color: reasonFilled
                          ? (isDark ? Colors.white70 : AppColors.textPrimary)
                          : AppColors.textTertiary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!reasonFilled) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              'Fill in the reason for leaving to enable this option.',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'Terms and Conditions',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Disclaimer — The last working day shall be determined as per '
          'the company\'s policy and may be subject to clearance procedures. '
          'Your resignation will be reviewed by HR before final acceptance.',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  // ---- Submit button ------------------------------------------------------

  Widget _buildSubmitButton() {
    final enabled = _canSubmit;
    return SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: enabled ? _submit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
              disabledForegroundColor: Colors.white.withOpacity(0.8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Text(
                    'Submit',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        )
        .animate()
        .fadeIn(duration: 220.ms)
        .slideY(begin: 0.1, end: 0, duration: 220.ms);
  }
}

/// Pill rendering of a single attached file: doc icon, name, size, and
/// (when [onRemove] is provided) a × button. Tapping the body opens the
/// file via [OpenFile]. Reused by both the form view (with remove) and the
/// submitted view (read-only — pass `onRemove: null`).
class _AttachmentChip extends StatelessWidget {
  final _Attachment attachment;
  final bool isDark;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;

  const _AttachmentChip({
    required this.attachment,
    required this.isDark,
    required this.onOpen,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Material(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white24 : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Iconsax.document_text, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    attachment.name,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _fmtBytes(attachment.sizeBytes),
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    color: AppColors.textTertiary,
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onRemove,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Iconsax.close_circle,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
