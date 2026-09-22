// Useful Links Screen — external statutory/utility portals (EPFO, ESI, UMANG).
//
// The employee's own paperwork (Form 16, Medical Health Card) lives in
// My Documents, reached from the drawer; this screen only hands off to
// third-party websites.
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class _UsefulLink {
  final String title;
  final String? subtitle;
  final String url;
  final IconData icon;
  final Color color;

  const _UsefulLink({
    required this.title,
    this.subtitle,
    required this.url,
    required this.icon,
    required this.color,
  });
}

class UsefulLinksScreen extends StatelessWidget {
  const UsefulLinksScreen({super.key});

  static const List<_UsefulLink> _links = [
    _UsefulLink(
      title: 'EPFO',
      subtitle: 'Member Portal Link',
      url: 'https://unifiedportal-mem.epfindia.gov.in/memberinterface/',
      icon: Iconsax.wallet_check,
      color: AppColors.success,
    ),
    _UsefulLink(
      title: 'ESI',
      subtitle: 'Member Portal Link',
      url: 'https://portal.esic.gov.in/EmployeePortal/login.aspx',
      icon: Iconsax.health,
      color: AppColors.info,
    ),
    _UsefulLink(
      title: 'UMANG App',
      subtitle: 'Member Portal Link',
      url: 'https://web.umang.gov.in/landing/',
      icon: Iconsax.mobile,
      color: AppColors.warning,
    ),
  ];

  Future<void> _openUrl(BuildContext context, String url) async {
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Link coming soon')));
      return;
    }
    final uri = Uri.parse(url);

    // Try external browser first, then fall back to the platform default
    // (in-app webview / chooser) if the OS rejects the external intent.
    Future<bool> tryLaunch(LaunchMode mode) async {
      try {
        return await launchUrl(uri, mode: mode);
      } catch (_) {
        return false;
      }
    }

    var ok = await tryLaunch(LaunchMode.externalApplication);
    if (!ok) {
      ok = await tryLaunch(LaunchMode.platformDefault);
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open $url'),
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
        title: Text('Useful Links', style: AppTextStyles.headlineLarge),
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
            for (int i = 0; i < _links.length; i++)
              _buildLinkCard(context, isDark, _links[i], i * 80),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkCard(
    BuildContext context,
    bool isDark,
    _UsefulLink link,
    int delayMs,
  ) {
    return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                onTap: () => _openUrl(context, link.url),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: link.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(link.icon, color: link.color, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              link.title,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                              ),
                            ),
                            if (link.subtitle != null &&
                                link.subtitle!.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                link.subtitle!,
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
                      Icon(
                        Iconsax.export_3,
                        size: 14,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(delay: Duration(milliseconds: delayMs))
        .slideY(begin: 0.05, end: 0);
  }
}
