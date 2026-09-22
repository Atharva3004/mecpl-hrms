// The employment-category selector that sits at the top of the Letters card
// in My Documents.
//
// Deliberately not a Material `DropdownButton`: that opens an overlay menu
// which floats over the card and breaks the accordion feel of the screen. This
// one expands *inline*, so the card grows to reveal the options and the letter
// rows below slide down with it — the same motion language as the group cards
// themselves (AnimatedSize + AnimatedRotation).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Employment category a letter is issued under. HR keeps a separate template
/// per category, so the same letter type resolves to a different document
/// depending on which one is selected.
enum LetterCategory {
  staff('Staff', 'Permanent & probation employees', Iconsax.profile_2user),
  apprentice('Apprentice', 'Trainees under apprenticeship', Iconsax.teacher),
  consultant(
    'Consultant',
    'Contract & retainer engagements',
    Iconsax.briefcase,
  );

  const LetterCategory(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;

  /// Query value sent to the API (`/letters/{type}?category=staff`).
  String get apiValue => name;
}

class LetterCategoryDropdown extends StatefulWidget {
  final LetterCategory value;
  final ValueChanged<LetterCategory> onChanged;

  /// Accent used for the selected state — passed in so the control picks up
  /// whatever colour its parent group card uses.
  final Color accent;

  const LetterCategoryDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    required this.accent,
  });

  @override
  State<LetterCategoryDropdown> createState() => _LetterCategoryDropdownState();
}

class _LetterCategoryDropdownState extends State<LetterCategoryDropdown> {
  bool _open = false;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _open = !_open);
  }

  void _select(LetterCategory category) {
    HapticFeedback.lightImpact();
    setState(() => _open = false);
    if (category != widget.value) widget.onChanged(category);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Iconsax.category_2,
                size: 12,
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.textTertiary,
              ),
              const SizedBox(width: 5),
              Text(
                'CATEGORY',
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // The control itself: a tinted pill that morphs (colour, border,
          // corner radius) as it opens, with the option list unfolding below.
          AnimatedContainer(
            duration: AppConstants.animNormal,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: _open
                  ? accent.withOpacity(isDark ? 0.10 : 0.05)
                  : (isDark
                        ? AppColors.darkSurfaceVariant
                        : AppColors.surfaceVariant),
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
              border: Border.all(
                color: _open
                    ? accent.withOpacity(0.55)
                    : (isDark ? AppColors.darkBorder : AppColors.border),
                width: _open ? 1.4 : 1,
              ),
              boxShadow: _open
                  ? [
                      BoxShadow(
                        color: accent.withOpacity(0.16),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: Column(
              children: [
                _buildTrigger(isDark, accent),
                AnimatedSize(
                  duration: AppConstants.animNormal,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _open
                      ? Column(
                          children: [
                            Divider(
                              height: 1,
                              thickness: 1,
                              indent: 10,
                              endIndent: 10,
                              color: isDark
                                  ? AppColors.darkBorder
                                  : AppColors.border,
                            ),
                            for (
                              int i = 0;
                              i < LetterCategory.values.length;
                              i++
                            )
                              _buildOption(
                                isDark,
                                accent,
                                LetterCategory.values[i],
                                i,
                              ),
                            const SizedBox(height: 4),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Collapsed row — shows the current selection and flips the chevron.
  ///
  /// Wrapped in its own transparent Material so the ripple paints *above* the
  /// pill's opaque fill; without it the splash lands on the card underneath
  /// and never shows.
  Widget _buildTrigger(bool isDark, Color accent) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              AnimatedContainer(
                duration: AppConstants.animNormal,
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withOpacity(_open ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                // Swaps in the icon of whichever category is selected, with a
                // scale+fade so the change is legible without a jump.
                child: AnimatedSwitcher(
                  duration: AppConstants.animFast,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Icon(
                    widget.value.icon,
                    key: ValueKey(widget.value),
                    size: 14,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppConstants.animFast,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Column(
                    key: ValueKey(widget.value),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.value.label,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        widget.value.description,
                        style: AppTextStyles.labelSmall.copyWith(
                          fontSize: 10.5,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: _open ? 0.5 : 0.0,
                duration: AppConstants.animNormal,
                curve: Curves.easeOutBack,
                child: Icon(
                  Iconsax.arrow_down_1,
                  size: 15,
                  color: _open
                      ? accent
                      : (isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One option row. Staggered by [index] so the list cascades open rather
  /// than appearing all at once.
  Widget _buildOption(
    bool isDark,
    Color accent,
    LetterCategory category,
    int index,
  ) {
    final selected = category == widget.value;

    return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _select(category),
            child: Container(
              margin: const EdgeInsets.fromLTRB(6, 4, 6, 0),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? accent.withOpacity(0.10) : Colors.transparent,
                borderRadius: BorderRadius.circular(AppConstants.radiusSM),
                border: Border.all(
                  color: selected
                      ? accent.withOpacity(0.35)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    category.icon,
                    size: 15,
                    color: selected
                        ? accent
                        : (isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      category.label,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected
                            ? accent
                            : (isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.textPrimary),
                      ),
                    ),
                  ),
                  // Tick pops in only for the active row.
                  AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: AppConstants.animNormal,
                    curve: Curves.easeOutBack,
                    child: Icon(Iconsax.tick_circle, size: 15, color: accent),
                  ),
                ],
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: 40 * index),
          duration: AppConstants.animFast,
        )
        .slideY(begin: -0.25, end: 0, curve: Curves.easeOutCubic);
  }
}
