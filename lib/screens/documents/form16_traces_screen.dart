// Form 16 (TRACES) viewer — reached from Useful Links > Form 16 > TRACES.
// Part A (TDS deducted/deposited) and Part B (salary breakup) are the two
// halves of the TRACES-issued certificate, each presented as a card with its
// own View / Download / Share actions.
//
// GET /form16/status decides what the user sees: a part marked available is
// fetched from /form16/download/{id} and its card goes live; a part marked
// unavailable renders as "Not available" with its actions disabled, and is
// never fetched.
//
// If an available part fails to download (offline, server error), the card
// falls back to the sample PDF bundled in assets/forms/ and says so, so the
// screen stays usable without pretending the sample is the real certificate.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/animations/page_transitions.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/file_saver.dart';
import '../../models/form16_status_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../payroll/payslip_full_screen.dart';

/// Static presentation details for one half of the certificate. Availability
/// and the download id come from the API, not from here.
class _PartMeta {
  final Form16Part part;
  final String description;
  final IconData icon;

  /// Bundled sample, used only if the API download fails.
  final String fallbackAsset;

  const _PartMeta({
    required this.part,
    required this.description,
    required this.icon,
    required this.fallbackAsset,
  });

  String get label => part.label;
  String get title => 'Form 16 — $label';
  String get fileName => fallbackAsset.split('/').last;
  String get heroTag => 'form16_${part.key}';
}

/// Per-card runtime state.
class _PartState {
  Form16PartStatus status = Form16PartStatus.unavailable;
  Uint8List? bytes;
  String? path;
  bool loading = true;

  /// True when [bytes] came from the bundled sample rather than the API.
  bool usingFallback = false;

  bool get ready => path != null;
}

class Form16TracesScreen extends StatefulWidget {
  const Form16TracesScreen({super.key});

  static Route<dynamic> route() => PageTransitions.sharedAxisTransition(
    page: const Form16TracesScreen(),
  );

  @override
  State<Form16TracesScreen> createState() => _Form16TracesScreenState();
}

class _Form16TracesScreenState extends State<Form16TracesScreen> {
  static const List<_PartMeta> _metas = [
    _PartMeta(
      part: Form16Part.partA,
      description: 'Summary of tax deducted and deposited against your PAN.',
      icon: Iconsax.receipt_2,
      fallbackAsset: 'assets/forms/form16_part_a.pdf',
    ),
    _PartMeta(
      part: Form16Part.partB,
      description: 'Salary breakup, exemptions and deductions.',
      icon: Iconsax.document_text,
      fallbackAsset: 'assets/forms/form16_part_b.pdf',
    ),
  ];

  final Map<Form16Part, _PartState> _states = {
    for (final meta in _metas) meta.part: _PartState(),
  };

  bool _loadingStatus = true;
  String? _statusError;
  String? _financialYear;
  String? _sharingLabel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadingStatus = true;
      _statusError = null;
      for (final state in _states.values) {
        state.loading = true;
      }
    });

    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loadingStatus = false;
        _statusError = 'Please log in again to view Form 16.';
      });
      return;
    }

    final status = await ApiService.fetchForm16Status(token: token);
    if (!mounted) return;

    if (status == null) {
      setState(() {
        _loadingStatus = false;
        _statusError = 'Could not check Form 16 availability.';
      });
      return;
    }

    setState(() {
      _loadingStatus = false;
      _financialYear = status.financialYear;
      for (final meta in _metas) {
        _states[meta.part]!.status = status.partStatus(
          Form16Source.traces,
          meta.part,
        );
      }
    });

    // Only fetch what the backend says exists.
    await Future.wait(_metas.map((meta) => _loadPart(token, meta)));
  }

  Future<void> _loadPart(String token, _PartMeta meta) async {
    final state = _states[meta.part]!;
    if (!state.status.isDownloadable) {
      if (mounted) setState(() => state.loading = false);
      return;
    }

    Uint8List? bytes = await ApiService.fetchForm16PdfBytes(
      token: token,
      id: state.status.id!,
    );
    var usingFallback = false;

    if (bytes == null) {
      bytes = await _loadFallbackAsset(meta);
      usingFallback = bytes != null;
    }

    String? path;
    if (bytes != null) {
      path = await _cacheToDisk(meta.fileName, bytes);
    }

    if (!mounted) return;
    setState(() {
      state.bytes = bytes;
      state.path = path;
      state.usingFallback = usingFallback;
      state.loading = false;
    });
  }

  Future<Uint8List?> _loadFallbackAsset(_PartMeta meta) async {
    try {
      final data = await rootBundle.load(meta.fallbackAsset);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  /// The viewer, Share and OpenFile all need a real path, so bytes get
  /// written to the temp dir before any of them can run.
  Future<String?> _cacheToDisk(String fileName, Uint8List bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  void _view(_PartMeta meta) {
    final state = _states[meta.part]!;
    final path = state.path;
    if (path == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PayslipFullScreen(
          filePath: path,
          heroTag: meta.heroTag,
          title: meta.title,
          shareSubject: meta.title,
          missingFileMessage: '${meta.label} is no longer available.',
          onDownload: () => _download(meta),
        ),
      ),
    );
  }

  Future<void> _share(_PartMeta meta) async {
    final state = _states[meta.part]!;
    final path = state.path;
    if (path == null || _sharingLabel != null) return;
    setState(() => _sharingLabel = meta.label);
    try {
      await Share.shareXFiles(
        [XFile(path, mimeType: 'application/pdf')],
        subject: meta.title,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open share sheet')),
      );
    } finally {
      if (mounted) setState(() => _sharingLabel = null);
    }
  }

  Future<void> _download(_PartMeta meta) async {
    final state = _states[meta.part]!;
    final bytes = state.bytes;
    if (bytes == null) return;
    try {
      final path = await FileSaver.save(bytes, meta.fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${meta.label} saved to ${FileSaver.locationLabel}'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusSM),
          ),
          action: SnackBarAction(
            label: 'OPEN FILE',
            textColor: Colors.white,
            onPressed: () async {
              final result = await OpenFile.open(path);
              if (!mounted) return;
              if (result.type != ResultType.done) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(result.message)));
              }
            },
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not download ${meta.fileName}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text('Form 16 — TRACES', style: AppTextStyles.headlineLarge),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(isDark),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loadingStatus) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_statusError != null) {
      return _ErrorState(
        message: _statusError!,
        isDark: isDark,
        onRetry: _load,
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.paddingMD,
        vertical: AppConstants.paddingMD,
      ),
      children: [
        if (_financialYear != null) _buildYearChip(isDark),
        for (int i = 0; i < _metas.length; i++)
          _buildPartCard(isDark, _metas[i], i * 100),
      ],
    );
  }

  Widget _buildYearChip(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.paddingMD),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.paddingSM + 2,
              vertical: AppConstants.paddingXS + 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            ),
            child: Text(
              'FY $_financialYear',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildPartCard(bool isDark, _PartMeta meta, int delayMs) {
    final state = _states[meta.part]!;
    final loading = state.loading;
    final ready = state.ready;
    final sharing = _sharingLabel == meta.label;

    // Three distinct states, and the subtitle has to tell them apart: still
    // fetching, backend says there is no such certificate, or usable.
    final String subtitle;
    if (loading) {
      subtitle = 'Checking…';
    } else if (!state.status.available) {
      subtitle = 'Not available';
    } else if (!ready) {
      subtitle = 'Could not be loaded.';
    } else if (state.usingFallback) {
      subtitle = 'Offline sample — could not reach the server.';
    } else {
      subtitle = meta.description;
    }

    return Padding(
          padding: const EdgeInsets.only(bottom: AppConstants.paddingMD),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusLG),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border,
              ),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: ready ? () => _view(meta) : null,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppConstants.radiusLG),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.paddingMD),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppConstants.paddingSM),
                          decoration: BoxDecoration(
                            color: ready
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : (isDark
                                          ? AppColors.darkSurfaceVariant
                                          : AppColors.surfaceVariant)
                                      .withValues(alpha: 1),
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusMD,
                            ),
                          ),
                          child: Icon(
                            meta.icon,
                            color: ready
                                ? AppColors.primary
                                : (isDark
                                      ? AppColors.darkTextTertiary
                                      : AppColors.textTertiary),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: AppConstants.paddingSM + 2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                meta.label,
                                style: AppTextStyles.titleMedium.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: AppTextStyles.caption.copyWith(
                                  color: !loading && !state.status.available
                                      ? AppColors.error
                                      : (isDark
                                            ? AppColors.darkTextSecondary
                                            : AppColors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (loading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (ready)
                          Icon(
                            Iconsax.arrow_right_3,
                            size: 18,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.textTertiary,
                          ),
                      ],
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                ),
                Row(
                  children: [
                    _buildAction(
                      isDark: isDark,
                      icon: Iconsax.eye,
                      label: 'View',
                      enabled: ready,
                      onTap: () => _view(meta),
                      corner: const BorderRadius.only(
                        bottomLeft: Radius.circular(AppConstants.radiusLG),
                      ),
                    ),
                    _buildDivider(isDark),
                    _buildAction(
                      isDark: isDark,
                      icon: Iconsax.document_download,
                      label: 'Download',
                      enabled: ready,
                      onTap: () => _download(meta),
                    ),
                    _buildDivider(isDark),
                    _buildAction(
                      isDark: isDark,
                      icon: Iconsax.share,
                      label: 'Share',
                      enabled: ready && !sharing,
                      busy: sharing,
                      onTap: () => _share(meta),
                      corner: const BorderRadius.only(
                        bottomRight: Radius.circular(AppConstants.radiusLG),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(delay: Duration(milliseconds: delayMs), duration: 350.ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _buildDivider(bool isDark) => Container(
    width: 1,
    height: 44,
    color: isDark ? AppColors.darkBorder : AppColors.border,
  );

  Widget _buildAction({
    required bool isDark,
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool busy = false,
    BorderRadius? corner,
  }) {
    final color = enabled
        ? AppColors.primary
        : (isDark ? AppColors.darkTextTertiary : AppColors.textTertiary);

    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: corner,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              else
                Icon(icon, size: 17, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final bool isDark;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.isDark,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // Must scroll for RefreshIndicator's pull gesture to reach it.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Icon(
          Iconsax.document_cloud,
          size: 48,
          color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
        ),
        const SizedBox(height: AppConstants.paddingSM),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppConstants.paddingMD),
        Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Iconsax.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }
}
