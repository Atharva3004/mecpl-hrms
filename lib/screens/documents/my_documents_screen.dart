// My Documents — the employee's own paperwork, reached from the drawer.
//
// Holds the document groups that used to sit under Useful Links (which is
// now purely external portals):
//   * Form 16          — TRACES (its own screen) and MECPL.
//   * Medical Health Card — the employee's card pulled off the server
//     (GET /my-documents -> /health-card/download/{id}), plus the bundled blank
//     claim forms shipped under `assets/forms/`.
//   * Letters          — the six HR letters (warning, confirmation, extension,
//     experience, promotion, appointment) fetched from /letters/{type}. HR
//     keeps a separate template per employment category, so this group carries
//     a Staff / Apprentice / Consultant selector that every row below it uses.
//
// Everything opens in the shared full-screen viewer (view / share / download).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/file_saver.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../payroll/payslip_full_screen.dart';
import 'form16_traces_screen.dart';
import 'letter_category_dropdown.dart';

/// A document that has to be fetched from the API rather than read out of the
/// bundle, so the row can show a spinner while it downloads.
enum _RemoteDoc { healthCard }

/// A child entry under a document group. Precedence when tapped:
/// [screen] (push it) > [remote] (fetch from the API) > [letter] (fetch
/// /letters/{slug} for the selected category) > [asset] (bundled PDF under
/// `assets/forms/`). With all four null the item is a placeholder
/// ("Coming soon").
class _DocItem {
  final String title;
  final String? asset;
  final Route<dynamic> Function()? screen;
  final _RemoteDoc? remote;

  /// Route slug for an HR letter — e.g. `warning` hits /letters/warning.
  final String? letter;

  /// Leading icon and tint. Both fall back to the parent group's when null,
  /// which is what the Form 16 / health-card rows do.
  final IconData? icon;
  final Color? color;

  const _DocItem(
    this.title, {
    this.asset,
    this.screen,
    this.remote,
    this.letter,
    this.icon,
    this.color,
  });
}

class _DocGroup {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final List<_DocItem> children;

  /// Whether the card shows the Staff / Apprentice / Consultant selector above
  /// its rows. Only Letters does — every one of its children resolves against
  /// whichever category is picked.
  final bool hasCategorySelector;

  const _DocGroup({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    required this.children,
    this.hasCategorySelector = false,
  });
}

class MyDocumentsScreen extends StatefulWidget {
  const MyDocumentsScreen({super.key});

  @override
  State<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends State<MyDocumentsScreen> {
  static const List<_DocGroup> _groups = [
    _DocGroup(
      title: 'Form 16',
      subtitle: 'Tax certificates',
      icon: Iconsax.receipt_2,
      color: AppColors.primary,
      children: [
        _DocItem('TRACES', screen: Form16TracesScreen.route),
        _DocItem('MECPL'),
      ],
    ),
    _DocGroup(
      title: 'Medical Health Card',
      subtitle: 'Card and claim forms',
      icon: Iconsax.heart,
      color: AppColors.error,
      children: [
        _DocItem('Medical Card', remote: _RemoteDoc.healthCard),
        _DocItem('Claim Form GPA', asset: 'assets/forms/claim_form_gpa.pdf'),
        _DocItem('Form A and B', asset: 'assets/forms/form_a_and_b.pdf'),
        // _DocItem('Claim Form EC', asset: 'assets/forms/claim_form_ec.pdf'),
      ],
    ),
    _DocGroup(
      title: 'Letters',
      subtitle: 'Issued by HR',
      icon: Iconsax.note_1,
      color: AppColors.info,
      hasCategorySelector: true,
      children: [
        _DocItem(
          'Warning Letter',
          letter: 'warning',
          icon: Iconsax.warning_2,
          color: AppColors.warning,
        ),
        _DocItem(
          'Confirmation Letter',
          letter: 'confirmation',
          icon: Iconsax.verify,
          color: AppColors.success,
        ),
        _DocItem(
          'Extension Letter',
          letter: 'extension',
          icon: Iconsax.calendar_add,
          color: AppColors.info,
        ),
        _DocItem(
          'Experience Letter',
          letter: 'experience',
          icon: Iconsax.medal_star,
          color: AppColors.secondary,
        ),
        _DocItem(
          'Promotion Letter',
          letter: 'promotion',
          icon: Iconsax.ranking,
          color: AppColors.directorColor,
        ),
        _DocItem(
          'Appointment Letter',
          letter: 'appointment',
          icon: Iconsax.clipboard_text,
          color: AppColors.primary,
        ),
      ],
    ),
  ];

  /// Titles of the expanded cards. Every group starts *closed* so the screen
  /// opens as a short list of headings the user can scan; a card reveals its
  /// contents only once tapped.
  final Set<String> _expanded = <String>{};

  /// Title of the item currently being fetched from the API, so its row can
  /// show a spinner and ignore repeat taps.
  String? _busyItem;

  /// Employment category the Letters group resolves its rows against. Staff is
  /// the common case, so it is the default.
  LetterCategory _category = LetterCategory.staff;

  /// Opens a document item. Screens are pushed, remote documents fetched,
  /// bundled assets cached to disk and shown in the shared viewer.
  Future<void> _openItem(BuildContext context, _DocItem item) async {
    final screen = item.screen;
    if (screen != null) {
      Navigator.of(context).push(screen());
      return;
    }

    if (item.remote == _RemoteDoc.healthCard) {
      await _openHealthCard(context, item);
      return;
    }

    if (item.letter != null) {
      await _openLetter(context, item);
      return;
    }

    final asset = item.asset;
    if (asset == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${item.title} — Coming soon')));
      return;
    }

    final fileName = asset.split('/').last;
    try {
      final data = await rootBundle.load(asset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PayslipFullScreen(
            filePath: file.path,
            heroTag: 'form_$fileName',
            title: item.title,
            shareSubject: item.title,
            missingFileMessage: '${item.title} is not available.',
            onDownload: () => _downloadForm(context, bytes, fileName),
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open ${item.title}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Fetches the employee's own medical health card and opens it in the shared
  /// viewer (view / share / download).
  ///
  /// Two hops, both authenticated: GET /my-documents says whether a card
  /// exists for the current financial year and gives its upload id, then
  /// /health-card/download/{id} returns the PDF. Nothing is bundled as a
  /// fallback here — an employee without a card should be told to contact HR,
  /// not shown a sample that looks like theirs.
  Future<void> _openHealthCard(BuildContext context, _DocItem item) async {
    if (_busyItem != null) return; // a fetch is already in flight
    final messenger = ScaffoldMessenger.of(context);
    final token = context.read<AuthProvider>().token ?? '';
    if (token.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please sign in again to view documents')),
      );
      return;
    }

    setState(() => _busyItem = item.title);
    try {
      final docs = await ApiService.fetchMyDocuments(token: token);
      if (!mounted) return;
      if (docs == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not load your documents. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      final card = docs.healthCard;
      if (!card.isDownloadable) {
        final fy = docs.financialYear;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              fy == null
                  ? 'No medical health card on file yet. Please contact HR.'
                  : 'No medical health card for FY $fy yet. Please contact HR.',
            ),
          ),
        );
        return;
      }

      final bytes = await ApiService.fetchHealthCardPdfBytes(
        token: token,
        id: card.id!,
      );
      if (!mounted) return;
      if (bytes == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not open the medical health card.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      // flutter_pdfview reads from disk, so cache the bytes first.
      final fileName = docs.financialYear == null
          ? 'medical_health_card.pdf'
          : 'medical_health_card_${docs.financialYear}.pdf';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted || !context.mounted) return;

      final title = docs.financialYear == null
          ? 'Medical Health Card'
          : 'Medical Health Card — FY ${docs.financialYear}';
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PayslipFullScreen(
            filePath: file.path,
            heroTag: 'health_card_${card.id}',
            title: title,
            shareSubject: title,
            missingFileMessage: 'Medical health card is no longer available.',
            onDownload: () => _downloadForm(context, bytes, fileName),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open the medical health card.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyItem = null);
    }
  }

  /// Fetches one HR letter for the category currently selected in the Letters
  /// card and opens it in the shared viewer.
  ///
  /// A missing letter is the ordinary case — most employees have never been
  /// issued a warning or a promotion letter — so a 404 gets a plain, neutral
  /// message rather than the red failure treatment.
  Future<void> _openLetter(BuildContext context, _DocItem item) async {
    if (_busyItem != null) return; // a fetch is already in flight
    final messenger = ScaffoldMessenger.of(context);
    final token = context.read<AuthProvider>().token ?? '';
    if (token.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please sign in again to view documents')),
      );
      return;
    }

    final category = _category;
    setState(() => _busyItem = item.title);
    try {
      final result = await ApiService.fetchLetterPdfBytes(
        token: token,
        type: item.letter!,
        category: category.apiValue,
      );
      if (!mounted) return;

      final bytes = result.bytes;
      if (bytes == null) {
        final missing = result.error == 'not_found';
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              missing
                  ? 'No ${item.title} on file for ${category.label}. Please contact HR.'
                  : 'Could not open the ${item.title}. Please try again.',
            ),
            backgroundColor: missing ? null : AppColors.error,
          ),
        );
        return;
      }

      // flutter_pdfview reads from disk, so cache the bytes first.
      final fileName = '${item.letter}_letter_${category.apiValue}.pdf';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted || !context.mounted) return;

      final title = '${item.title} — ${category.label}';
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PayslipFullScreen(
            filePath: file.path,
            heroTag: 'letter_${item.letter}_${category.apiValue}',
            title: title,
            shareSubject: title,
            missingFileMessage: '${item.title} is no longer available.',
            onDownload: () => _downloadForm(context, bytes, fileName),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not open the ${item.title}.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyItem = null);
    }
  }

  /// Writes the document bytes somewhere the user can find them and offers an
  /// OPEN FILE action.
  Future<void> _downloadForm(
    BuildContext context,
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      final filePath = await FileSaver.save(bytes, fileName);
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to ${FileSaver.locationLabel}'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'OPEN FILE',
            textColor: Colors.white,
            onPressed: () async {
              final result = await OpenFile.open(filePath);
              if (!context.mounted) return;
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
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not download $fileName'),
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
        title: Text('My Documents', style: AppTextStyles.headlineLarge),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.paddingMD,
          vertical: AppConstants.paddingMD,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < _groups.length; i++)
              _buildGroupCard(context, isDark, _groups[i], i * 80),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(
    BuildContext context,
    bool isDark,
    _DocGroup group,
    int delayMs,
  ) {
    final isExpanded = _expanded.contains(group.title);

    return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            // The border and a faint tinted glow track the open state, so an
            // expanded card reads as the active one at a glance.
            child: AnimatedContainer(
              duration: AppConstants.animNormal,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                border: Border.all(
                  color: isExpanded
                      ? group.color.withOpacity(0.45)
                      : (isDark ? AppColors.darkBorder : AppColors.border),
                  width: isExpanded ? 1.3 : 1,
                ),
                boxShadow: isExpanded
                    ? [
                        BoxShadow(
                          color: group.color.withOpacity(0.10),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : const [],
              ),
              child: Column(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (!_expanded.remove(group.title)) {
                          _expanded.add(group.title);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: AppConstants.animNormal,
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: group.color.withOpacity(
                                isExpanded ? 0.22 : 0.12,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              group.icon,
                              color: group.color,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.title,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: isDark
                                        ? AppColors.darkTextPrimary
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                if (group.subtitle != null &&
                                    group.subtitle!.isNotEmpty) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    group.subtitle!,
                                    style: AppTextStyles.labelSmall.copyWith(
                                      fontSize: 11,
                                      color: isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          AnimatedRotation(
                            turns: isExpanded ? 0.5 : 0.0,
                            duration: AppConstants.animNormal,
                            curve: Curves.easeOutBack,
                            child: Icon(
                              Icons.expand_more,
                              size: 18,
                              color: isExpanded
                                  ? group.color
                                  : (isDark
                                        ? AppColors.darkTextTertiary
                                        : AppColors.textTertiary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // The card grows to fit its contents; the contents themselves
                  // fade up as it grows so nothing is legible before there is
                  // room for it.
                  AnimatedSize(
                    duration: AppConstants.animNormal,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: isExpanded
                        ? _buildGroupBody(
                            context,
                            isDark,
                            group,
                          ).animate().fadeIn(duration: AppConstants.animNormal)
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(delay: Duration(milliseconds: delayMs))
        .slideY(begin: 0.05, end: 0);
  }

  /// The expanded contents of a group card: the category selector (Letters
  /// only) followed by the document rows.
  ///
  /// For a group with a selector the rows are keyed on the current category,
  /// so switching Staff → Apprentice cross-fades and re-staggers them. Nothing
  /// in the row text changes, but the motion is the acknowledgement that the
  /// tap landed — otherwise picking a category looks like it did nothing until
  /// the next fetch.
  Widget _buildGroupBody(BuildContext context, bool isDark, _DocGroup group) {
    final divider = Divider(
      height: 1,
      thickness: 1,
      color: isDark ? AppColors.darkBorder : AppColors.border,
    );

    final rows = Column(
      key: group.hasCategorySelector ? ValueKey(_category) : null,
      children: [
        for (int i = 0; i < group.children.length; i++)
          _buildDocRow(context, isDark, group.children[i], group, i),
      ],
    );

    return Column(
      children: [
        divider,
        if (group.hasCategorySelector) ...[
          LetterCategoryDropdown(
            value: _category,
            accent: group.color,
            onChanged: (value) => setState(() => _category = value),
          ),
          divider,
        ],
        if (group.hasCategorySelector)
          AnimatedSwitcher(
            duration: AppConstants.animNormal,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            // Top-aligned so the outgoing and incoming lists overlap from the
            // same edge while they cross-fade.
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, if (current != null) current],
            ),
            child: rows,
          )
        else
          rows,
      ],
    );
  }

  Widget _buildDocRow(
    BuildContext context,
    bool isDark,
    _DocItem item,
    _DocGroup parent,
    int index,
  ) {
    // Trailing icon advertises what the tap does: open a screen, fetch the
    // employee's own document, open a bundled PDF, or nothing yet.
    final busy = _busyItem == item.title;
    final trailingIcon = item.screen != null
        ? Iconsax.arrow_right_3
        : item.remote != null || item.letter != null
        ? Iconsax.document_download
        : item.asset != null
        ? Iconsax.document_text
        : Iconsax.clock;
    // Letters carry their own icon and tint; the older rows fall back to the
    // group's arrow, which is what they have always shown.
    final tint = item.color ?? parent.color;
    final leadingIcon = item.icon ?? Iconsax.arrow_right_3;
    final tinted = item.icon != null;

    final row = InkWell(
      onTap: busy ? null : () => _openItem(context, item),
      child: Padding(
        padding: EdgeInsets.fromLTRB(tinted ? 14 : 30, 12, 14, 12),
        child: Row(
          children: [
            // A tinted chip for letters reads as a document type at a glance;
            // it also dims while its own fetch is in flight.
            AnimatedOpacity(
              opacity: busy ? 0.5 : 1,
              duration: AppConstants.animFast,
              child: tinted
                  ? Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: tint.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(leadingIcon, size: 16, color: tint),
                    )
                  : Icon(leadingIcon, size: 18, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.title,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: busy
                  ? SizedBox(
                      key: const ValueKey('busy'),
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tint,
                      ),
                    )
                  : Icon(
                      trailingIcon,
                      key: ValueKey(trailingIcon.codePoint),
                      size: 18,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.textTertiary,
                    ),
            ),
          ],
        ),
      ),
    );

    // Rows cascade in as the card opens. This replays only when the subtree is
    // rebuilt from scratch — expanding the card, or switching category — not on
    // an unrelated setState such as a spinner starting, so it never flickers.
    return row
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: 40 * index),
          duration: AppConstants.animNormal,
        )
        .slideX(begin: 0.07, end: 0, curve: Curves.easeOutCubic);
  }
}
