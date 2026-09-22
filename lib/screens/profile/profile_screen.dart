// Profile Screen - Employee Profile Management
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../models/role_model.dart';
// import '../settings/settings_screen.dart';
// import '../notifications/notifications_screen.dart';
import '../../models/user_model.dart';
import '../../services/api_service.dart';
import '../../widgets/common/custom_loader.dart';
// import 'achievements_screen.dart';
// import 'documents_screen.dart';

class ProfileScreen extends StatefulWidget {
  final UserModel? user;
  const ProfileScreen({super.key, this.user});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Holds the full employee record fetched from /employee. The login response
  // is thin (no dob / personal_address), so we re-fetch on screen open and
  // overlay any fields the cached user is missing.
  UserModel? _enrichedUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchFullProfile());
  }

  Future<void> _fetchFullProfile() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    final baseUser = widget.user ?? auth.currentUser;
    if (token == null || baseUser == null) return;

    // Skip the call if the cached user already has both fields populated.
    final hasDob = baseUser.dob != null;
    final hasAddress = baseUser.address != null && baseUser.address!.isNotEmpty;
    if (hasDob && hasAddress) return;

    try {
      final response = await ApiService.getEmployees(token);
      if (!mounted || !response.isSuccess || response.data == null) return;
      final employees = ApiService.parseEmployeesFromResponse(response.data!);
      final match = employees.firstWhere(
        (e) => e.id == baseUser.id || e.employeeId == baseUser.employeeId,
        orElse: () => baseUser,
      );
      if (!mounted) return;
      // Merge: never let a null/empty from /employee clobber a good value
      // from the login response. Prefer base for everything; only fill in
      // dob/address from the enriched record when base lacks them.
      final merged = baseUser.copyWith(
        dob: baseUser.dob ?? match.dob,
        address: (baseUser.address != null && baseUser.address!.isNotEmpty)
            ? baseUser.address
            : (match.address != null && match.address!.isNotEmpty
                  ? match.address
                  : null),
      );
      setState(() => _enrichedUser = merged);
    } catch (_) {
      // Silent — the screen still renders with whatever the cached user has.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        final currentUser = auth.currentUser;
        final baseUser = widget.user ?? currentUser;
        final displayUser = _enrichedUser ?? baseUser;
        final isOwnProfile = widget.user == null || widget.user?.id == currentUser?.id;

        if (displayUser == null) {
          return const Scaffold(body: CustomLoader(size: 60));
        }

        return Scaffold(
          backgroundColor: isDark
              ? AppColors.darkBackground
              : AppColors.background,
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Profile Header
                SliverToBoxAdapter(
                  child: _buildProfileHeader(
                    context,
                    displayUser,
                    isDark,
                    isOwnProfile: widget.user == null,
                  ),
                ),

                // Quick Stats
                // SliverToBoxAdapter(child: _buildQuickStats(context, isDark)),

                // Personal Information
                SliverToBoxAdapter(
                  child: _buildPersonalInfo(context, displayUser, isDark),
                ),

                // Menu Items
                // if (isOwnProfile)
                //   SliverToBoxAdapter(child: _buildMenuSection(context, isDark)),

                // Work Information
                // SliverToBoxAdapter(
                //   child: _buildWorkInfo(context, displayUser, isDark),
                // ),

                // Logout Button
                if (widget.user == null)
                  SliverToBoxAdapter(
                    child: _buildLogoutButton(context, auth, isDark),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileHeader(
    BuildContext context,
    UserModel displayUser,
    bool isDark, {
    bool isOwnProfile = true,
  }) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canPop) ...[
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              // Avatar
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    displayUser.initials,
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayUser.fullName,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).animate().fadeIn(delay: 100.ms),
                    const SizedBox(height: 4),
                    Text(
                      '${displayUser.designation ?? 'Employee'} | ${displayUser.department ?? 'N/A'}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).animate().fadeIn(delay: 150.ms),
                    const SizedBox(height: 8),
                    Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(
                                  AppConstants.radiusFull,
                                ),
                              ),
                              child: Text(
                                displayUser.role.displayName,
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '#EMP${displayUser.employeeId ?? "N/A"}',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: Colors.white.withOpacity(0.8),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        )
                        .animate()
                        .fadeIn(delay: 200.ms)
                        .slideX(begin: -0.2, end: 0),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(BuildContext context, bool isDark) {
    final stats = [
      {'label': 'Days Worked', 'value': '22'},
      {'label': 'Leave Balance', 'value': '12'},
      {'label': 'Projects', 'value': '5'},
    ];

    return Padding(
      padding: const EdgeInsets.all(AppConstants.paddingLG),
      child: Row(
        children: stats.asMap().entries.map((entry) {
          final index = entry.key;
          final stat = entry.value;

          return Expanded(
            child:
                Container(
                      margin: EdgeInsets.only(
                        right: index < stats.length - 1 ? 12 : 0,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurface
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMD,
                        ),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.border,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            stat['value']!,
                            style: AppTextStyles.headlineMedium.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            stat['label']!,
                            style: AppTextStyles.caption.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    )
                    .animate(delay: Duration(milliseconds: 100 * index))
                    .fadeIn()
                    .slideY(begin: 0.2, end: 0),
          );
        }).toList(),
      ),
    );
  }

  // Widget _buildMenuSection(BuildContext context, bool isDark) {
  //   final menuItems = [
  //     {
  //       'icon': Iconsax.notification,
  //       'label': 'Notifications',
  //       'badge': '3',
  //       'screen': const NotificationsScreen(),
  //     },
  //     {
  //       'icon': Iconsax.setting,
  //       'label': 'Settings',
  //       'badge': null,
  //       'screen': const SettingsScreen(),
  //     },
  //     {
  //       'icon': Iconsax.document_text,
  //       'label': 'Documents',
  //       'badge': null,
  //       'screen': const DocumentsScreen(),
  //     },
  //     {
  //       'icon': Iconsax.medal_star,
  //       'label': 'Achievements',
  //       'badge': null,
  //       'screen': const AchievementsScreen(),
  //  },
  //  ];

  //   return Padding(
  //     padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingLG),
  //     child: Container(
  //       decoration: BoxDecoration(
  //         color: isDark ? AppColors.darkSurface : AppColors.surface,
  //         borderRadius: BorderRadius.circular(AppConstants.radiusLG),
  //         border: Border.all(
  //           color: isDark ? AppColors.darkBorder : AppColors.border,
  //         ),
  //       ),
  //       child: Column(
  //         children: menuItems.asMap().entries.map((entry) {
  //           final index = entry.key;
  //           final item = entry.value;

  //           return Column(
  //             children: [
  //               ListTile(
  //                 dense: true,
  //                 contentPadding: const EdgeInsets.symmetric(
  //                   horizontal: 16,
  //                   vertical: 0,
  //                 ),
  //                 visualDensity: const VisualDensity(
  //                   horizontal: 0,
  //                   vertical: -4,
  //                 ),
  //                 leading: Container(
  //                   width: 36,
  //                   height: 36,
  //                   decoration: BoxDecoration(
  //                     color: AppColors.primary.withOpacity(0.1),
  //                     borderRadius: BorderRadius.circular(10),
  //                   ),
  //                   child: Icon(
  //                     item['icon'] as IconData,
  //                     color: AppColors.primary,
  //                     size: 18,
  //                   ),
  //                 ),
  //                 title: Text(
  //                   item['label'] as String,
  //                   style: AppTextStyles.titleSmall.copyWith(
  //                     color: Theme.of(context).colorScheme.onSurface,
  //                   ),
  //                 ),
  //                 trailing: Row(
  //                   mainAxisSize: MainAxisSize.min,
  //                   children: [
  //                     if (item['badge'] != null)
  //                       Container(
  //                         padding: const EdgeInsets.symmetric(
  //                           horizontal: 6,
  //                           vertical: 3,
  //                         ),
  //                         decoration: BoxDecoration(
  //                           color: AppColors.error,
  //                           borderRadius: BorderRadius.circular(
  //                             AppConstants.radiusFull,
  //                           ),
  //                         ),
  //                         child: Text(
  //                           item['badge'] as String,
  //                           style: AppTextStyles.caption.copyWith(
  //                             color: Colors.white,
  //                             fontSize: 10,
  //                           ),
  //                         ),
  //                       ),
  //                     const SizedBox(width: 8),
  //                     Icon(
  //                       Iconsax.arrow_right,
  //                       color: isDark
  //                           ? AppColors.darkTextTertiary
  //                           : AppColors.textTertiary,
  //                       size: 16,
  //                     ),
  //                   ],
  //                 ),
  //                 onTap: () {
  //                   final screen = item['screen'];
  //                   if (screen != null) {
  //                     Navigator.push(
  //                       context,
  //                       MaterialPageRoute(builder: (_) => screen as Widget),
  //                     );
  //                   }
  //                 },
  //               ),
  //               if (index < menuItems.length - 1)
  //                 Divider(
  //                   height: 1,
  //                   indent: 72,
  //                   color: isDark ? AppColors.darkBorder : AppColors.border,
  //                 ),
  //             ],
  //           );
  //         }).toList(),
  //       ),
  //     ).animate().fadeIn(delay: 400.ms),
  //   );
  // }

  Widget _buildPersonalInfo(BuildContext context, user, bool isDark) {
    final info = [
      {
        'icon': Iconsax.sms,
        'label': 'Email',
        'value': user?.email ?? 'email@example.com',
      },
      {
        'icon': Iconsax.call,
        'label': 'Phone',
        'value': user?.phone ?? '+91 98765 43210',
      },
      {
        'icon': Iconsax.calendar,
        'label': 'Date of Birth',
        'value': user?.dob != null
            ? DateFormat('MMM dd, yyyy').format(user!.dob!)
            : 'N/A',
      },
      {
        'icon': Iconsax.location,
        'label': 'Address',
        'value': (user?.address != null && user!.address!.isNotEmpty)
            ? user.address
            : 'N/A',
      },
    ];

    return Padding(
      padding: const EdgeInsets.all(AppConstants.paddingLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal Information',
            style: AppTextStyles.titleLarge.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusLG),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border,
              ),
            ),
            child: Column(
              children: info.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item['icon'] as IconData,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.4),
                            size: 20,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['label'] as String,
                                  style: AppTextStyles.caption.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.5),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item['value'] as String,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (index < info.length - 1)
                      Divider(
                        height: 1,
                        color: isDark ? AppColors.darkBorder : AppColors.border,
                      ),
                  ],
                );
              }).toList(),
            ),
          ).animate().fadeIn(delay: 500.ms),
        ],
      ),
    );
  }

  Widget _buildWorkInfo(BuildContext context, user, bool isDark) {
    final info = [
      {
        'icon': Iconsax.building,
        'label': 'Department',
        'value': user?.department ?? 'Engineering',
      },
      {
        'icon': Iconsax.briefcase,
        'label': 'Employee ID',
        'value': user?.employeeId ?? 'MECPL007',
      },
      {
        'icon': Iconsax.calendar,
        'label': 'Joining Date',

        'value': user?.joinDate != null
            ? DateFormat('MMM dd, yyyy').format(user!.joinDate!)
            : 'N/A',
      },
      // {'icon': Iconsax.people, 'label': 'Reporting To', 'value': 'Priya Patel'},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Work Information',
            style: AppTextStyles.titleLarge.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusLG),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border,
              ),
            ),
            child: Column(
              children: info.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item['icon'] as IconData,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.4),
                            size: 20,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['label'] as String,
                                  style: AppTextStyles.caption.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.5),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item['value'] as String,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (index < info.length - 1)
                      Divider(
                        height: 1,
                        color: isDark ? AppColors.darkBorder : AppColors.border,
                      ),
                  ],
                );
              }).toList(),
            ),
          ).animate().fadeIn(delay: 600.ms),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(
    BuildContext context,
    AuthProvider auth,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.paddingLG),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: OutlinedButton.icon(
          onPressed: () async {
            await auth.logout();
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            ),
          ),
          icon: const Icon(Iconsax.logout),
          label: const Text('Logout'),
        ),
      ).animate().fadeIn(delay: 700.ms),
    );
  }
}
