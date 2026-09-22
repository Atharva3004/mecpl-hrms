// Full-screen payslip viewer. Pushed when the user taps the inline preview
// on either My Payslip or Employee Payslip. Pinch-zoom + page swipe enabled,
// with Share and Download actions in the app bar so the user can act on the
// same PDF they're looking at without bouncing back.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class PayslipFullScreen extends StatefulWidget {
  /// Path to the cached PDF on disk. Required — caller is expected to have
  /// already fetched and cached the bytes via PayslipPdfView's onReady.
  final String filePath;

  /// Hero tag — must match the inline preview tile's tag for the shared-
  /// element transition.
  final String heroTag;

  /// Pretty title displayed in the app bar (e.g. "Payslip — April 2026").
  final String title;

  /// Suggested filename for the Share sheet's subject line.
  final String shareSubject;

  /// Called when the user taps the Download action. Parent owns the actual
  /// save flow (it already has the right credentials/parameters cached) so
  /// this widget stays agnostic.
  final VoidCallback? onDownload;

  /// Shown when the cached file no longer exists on disk. Defaults to the
  /// payslip wording; other callers (e.g. bundled claim forms) override it.
  final String missingFileMessage;

  const PayslipFullScreen({
    super.key,
    required this.filePath,
    required this.heroTag,
    required this.title,
    required this.shareSubject,
    this.onDownload,
    this.missingFileMessage = 'Payslip file is no longer available.',
  });

  @override
  State<PayslipFullScreen> createState() => _PayslipFullScreenState();
}

class _PayslipFullScreenState extends State<PayslipFullScreen> {
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await Share.shareXFiles(
        [XFile(widget.filePath, mimeType: 'application/pdf')],
        subject: widget.shareSubject,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open share sheet')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _openExternally() async {
    final result = await OpenFile.open(widget.filePath);
    if (!mounted) return;
    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final exists = File(widget.filePath).existsSync();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: AppTextStyles.titleMedium.copyWith(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Open in another app',
            // Explicit white (dimmed when disabled) so the global icon theme
            // can't tint these dark against the black app bar.
            icon: Icon(
              Iconsax.export_3,
              color: exists ? Colors.white : Colors.white38,
            ),
            onPressed: exists ? _openExternally : null,
          ),
          IconButton(
            tooltip: 'Share',
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    Iconsax.share,
                    color: exists ? Colors.white : Colors.white38,
                  ),
            onPressed: exists && !_sharing ? _share : null,
          ),
          if (widget.onDownload != null)
            IconButton(
              tooltip: 'Download',
              icon: const Icon(
                Iconsax.document_download,
                color: Colors.white,
              ),
              onPressed: widget.onDownload,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: exists
          ? Hero(
              tag: widget.heroTag,
              child: PDFView(
                filePath: widget.filePath,
                enableSwipe: true,
                swipeHorizontal: true,
                pageSnap: true,
                pageFling: true,
                autoSpacing: true,
                fitPolicy: FitPolicy.BOTH,
              ),
            )
                .animate()
                .fadeIn(duration: 280.ms, curve: Curves.easeOut)
                .scale(
                  begin: const Offset(0.98, 0.98),
                  end: const Offset(1, 1),
                  duration: 280.ms,
                  curve: Curves.easeOutCubic,
                )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Iconsax.document_cloud,
                    color: AppColors.textTertiary,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.missingFileMessage,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
