// Inline PDF preview tile for the payslip screens.
//
// Fetches the payslip PDF bytes for the given (empId, month, type) tuple,
// writes them to a tmp file (flutter_pdfview requires a file path on disk),
// then renders the first page in a fixed-height tile. Tapping the tile
// notifies the parent so it can push the full-screen viewer.
//
// Caches the tmp path on the State so repeated tap-to-open doesn't re-fetch.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../services/api_service.dart';

typedef PayslipBytesLoader = Future<Uint8List?> Function();

class PayslipPdfView extends StatefulWidget {
  /// Stable identifier for the (employee + month + type) combination. When
  /// this changes, the cached file is invalidated and the bytes are re-fetched.
  final String cacheKey;

  /// Returns the PDF bytes. Wrapped in a callback so this widget doesn't
  /// need to know about auth/empId plumbing.
  final PayslipBytesLoader loader;

  /// Fixed visible height of the embedded preview tile.
  final double height;

  /// Called when the cached PDF is ready (path on disk). Parent uses this
  /// path to drive the share / open-file flows without re-fetching.
  final ValueChanged<String>? onReady;

  /// Called when the user taps the preview tile.
  final VoidCallback? onTap;

  /// Hero tag for the cross-route shared element animation.
  final String heroTag;

  const PayslipPdfView({
    super.key,
    required this.cacheKey,
    required this.loader,
    required this.heroTag,
    this.height = 420,
    this.onReady,
    this.onTap,
  });

  @override
  State<PayslipPdfView> createState() => _PayslipPdfViewState();
}

class _PayslipPdfViewState extends State<PayslipPdfView> {
  String? _filePath;
  bool _loading = true;
  String? _error;
  String? _activeCacheKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PayslipPdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      _load();
    }
  }

  Future<void> _load() async {
    final key = widget.cacheKey;
    _activeCacheKey = key;
    setState(() {
      _loading = true;
      _error = null;
      _filePath = null;
    });

    try {
      final bytes = await widget.loader();
      // Avoid racing against a stale fetch when cacheKey churned mid-flight.
      if (!mounted || _activeCacheKey != key) return;
      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Could not load payslip PDF.';
        });
        return;
      }
      final dir = await getTemporaryDirectory();
      final safeKey = key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file = File('${dir.path}/payslip_$safeKey.pdf');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted || _activeCacheKey != key) return;
      setState(() {
        _loading = false;
        _filePath = file.path;
      });
      widget.onReady?.call(file.path);
    } catch (e) {
      if (!mounted || _activeCacheKey != key) return;
      setState(() {
        _loading = false;
        _error = 'Could not load payslip PDF.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shellColor = isDark ? AppColors.darkSurface : Colors.white;
    final borderColor = isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0);

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: shellColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_loading)
            _ShimmerPlaceholder(isDark: isDark)
          else if (_error != null)
            _ErrorBlock(message: _error!, onRetry: _load, isDark: isDark)
          else if (_filePath != null)
            // Hero shares the rendered PDF tile with the full-screen route.
            Hero(
              tag: widget.heroTag,
              child: PDFView(
                key: ValueKey(_filePath),
                filePath: _filePath!,
                fitPolicy: FitPolicy.WIDTH,
                fitEachPage: true,
                autoSpacing: false,
                pageSnap: false,
                swipeHorizontal: false,
                enableSwipe: false,
                pageFling: false,
              ),
            )
                .animate()
                .fadeIn(duration: 320.ms, curve: Curves.easeOut)
                .scale(
                  begin: const Offset(0.96, 0.96),
                  end: const Offset(1, 1),
                  duration: 320.ms,
                  curve: Curves.easeOutCubic,
                ),
          // Transparent tap layer on top so the user can tap anywhere on the
          // preview to expand. PDFView swallows pointer events itself, so
          // overlaying lets the tap reach our handler.
          if (_filePath != null)
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          // Subtle "tap to expand" hint chip in the bottom-right corner.
          if (_filePath != null)
            Positioned(
              right: 10,
              bottom: 10,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Iconsax.maximize_4,
                        size: 12,
                        color: Colors.white,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Tap to expand',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(delay: 180.ms, duration: 260.ms)
                    .slideY(begin: 0.3, end: 0, duration: 260.ms),
              ),
            ),
        ],
      ),
    );
  }
}

/// Convenience helper for callers that already use `ApiService` — avoids
/// repeating the loader closure at every call site.
PayslipBytesLoader buildApiPayslipLoader({
  required String token,
  required String processMonth,
  required String empId,
  required String payslipType,
}) {
  return () => ApiService.fetchPayslipPdfBytes(
        token: token,
        processMonth: processMonth,
        empId: empId,
        payslipType: payslipType,
      );
}

class _ShimmerPlaceholder extends StatelessWidget {
  final bool isDark;
  const _ShimmerPlaceholder({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final baseColor = isDark ? Colors.white12 : const Color(0xFFEFEFEF);
    final highlightColor = isDark ? Colors.white24 : const Color(0xFFF7F7F7);
    return Container(
      color: baseColor,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(height: 12),
          Text(
            'Rendering payslip…',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .shimmer(
          duration: 1100.ms,
          color: highlightColor,
        );
  }
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool isDark;
  const _ErrorBlock({
    required this.message,
    required this.onRetry,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Iconsax.warning_2, size: 36, color: Color(0xFFF43F5E)),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white70 : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Iconsax.refresh, size: 16),
            label: const Text('Retry'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
