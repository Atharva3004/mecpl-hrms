// Admin-only Permission Management screen.
// Lets an admin toggle dashboard quick-action buttons per user.
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/quick_action_permission.dart';
import '../../models/role_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common/custom_loader.dart';

class PermissionManagementScreen extends StatefulWidget {
  const PermissionManagementScreen({super.key});

  @override
  State<PermissionManagementScreen> createState() =>
      _PermissionManagementScreenState();
}

class _PermissionManagementScreenState
    extends State<PermissionManagementScreen> {
  List<UserModel> _allUsers = [];
  List<UserModel> _filteredUsers = [];
  bool _isLoading = true;
  String? _loadError;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final token = context.read<AuthProvider>().token;
      if (token == null) {
        throw Exception('You are not logged in.');
      }
      final response = await ApiService.getEmployees(token);
      if (!response.isSuccess || response.data == null) {
        throw Exception(response.error ?? 'Failed to load users');
      }
      final users = ApiService.parseEmployeesFromResponse(response.data!);
      if (!mounted) return;
      setState(() {
        _allUsers = users;
        _filteredUsers = users;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filteredUsers = _allUsers.where((u) {
        final name = u.fullName.toLowerCase();
        final code = (u.employeeId ?? '').toLowerCase();
        return name.contains(q) || code.contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text(
          'Permission Management',
          style: AppTextStyles.headlineMedium.copyWith(
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            color: isDark ? Colors.white : AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CustomLoader(size: 60))
          : _loadError != null
          ? _buildError(isDark)
          : Column(
              children: [
                _buildSearch(isDark),
                Expanded(child: _buildUserList(isDark)),
              ],
            ),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingLG),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Iconsax.warning_2, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'Failed to load',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadUsers, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.paddingMD),
      child: TextField(
        controller: _searchController,
        style: AppTextStyles.bodyMedium.copyWith(
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Search by name or employee code',
          prefixIcon: const Icon(Iconsax.search_normal_1, size: 18),
          filled: true,
          fillColor: isDark ? AppColors.darkSurface : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.border,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserList(bool isDark) {
    // +1 leading slot for the pinned "All Users" tile.
    final total = _filteredUsers.length + 1;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMD),
      itemCount: total,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        if (i == 0) return _AllUsersTile(isDark: isDark);
        final u = _filteredUsers[i - 1];
        return _UserTile(user: u, isDark: isDark);
      },
    );
  }
}

class _AllUsersTile extends StatelessWidget {
  final bool isDark;
  const _AllUsersTile({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const UserPermissionEditorScreen(isGlobal: true),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Iconsax.people,
                  color: Colors.white,
                  size: 15,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All Users (Global Defaults)',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Applies to everyone unless overridden per user',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final UserModel user;
  final bool isDark;
  const _UserTile({required this.user, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppColors.darkSurface : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UserPermissionEditorScreen(user: user),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primary.withOpacity(0.15),
                child: Text(
                  user.initials,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      [
                        if ((user.employeeId ?? '').isNotEmpty)
                          '#${user.employeeId}',
                        user.role.displayName,
                      ].join(' · '),
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class UserPermissionEditorScreen extends StatefulWidget {
  final UserModel? user;
  final bool isGlobal;
  const UserPermissionEditorScreen({
    super.key,
    this.user,
    this.isGlobal = false,
  }) : assert(
         (user != null) ^ isGlobal,
         'Provide exactly one of user or isGlobal=true',
       );

  @override
  State<UserPermissionEditorScreen> createState() =>
      _UserPermissionEditorScreenState();
}

class _UserPermissionEditorScreenState
    extends State<UserPermissionEditorScreen> {
  Map<String, bool> _permissions = {};
  bool _isLoading = true;
  String? _loadError;
  final Set<String> _savingKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final token = context.read<AuthProvider>().token;
      if (token == null) throw Exception('You are not logged in.');
      final permProvider = context.read<PermissionProvider>();
      final perms = widget.isGlobal
          ? await permProvider.fetchGlobal(token: token)
          : await permProvider.fetchForTargetUser(
              targetUserId: widget.user!.id,
              token: token,
            );
      if (!mounted) return;
      setState(() => _permissions = perms);
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isEnabled(String key) => _permissions[key] ?? true;

  Future<void> _onToggle(String key, bool value) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    setState(() => _savingKeys.add(key));
    final perms = context.read<PermissionProvider>();
    if (widget.isGlobal) {
      await perms.setGlobalPermission(
        actionKey: key,
        enabled: value,
        token: token,
        localState: _permissions,
        onStateChange: (updated) {
          if (!mounted) return;
          setState(() => _permissions = Map<String, bool>.from(updated));
        },
      );
    } else {
      await perms.setTargetUserPermission(
        targetUserId: widget.user!.id,
        actionKey: key,
        enabled: value,
        token: token,
        localState: _permissions,
        onStateChange: (updated) {
          if (!mounted) return;
          setState(() => _permissions = Map<String, bool>.from(updated));
        },
      );
    }
    if (!mounted) return;
    setState(() => _savingKeys.remove(key));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grouped = QuickActionCatalog.groupedBySection();

    final title = widget.isGlobal ? 'All Users' : widget.user!.fullName;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text(
          title,
          style: AppTextStyles.headlineMedium.copyWith(
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            color: isDark ? Colors.white : AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CustomLoader(size: 60))
          : _loadError != null
          ? _buildError(isDark)
          : ListView(
              padding: const EdgeInsets.all(AppConstants.paddingMD),
              children: [
                _buildHeaderCard(isDark),
                const SizedBox(height: 16),
                for (final section in grouped.keys) ...[
                  _buildSectionTitle(section, isDark),
                  const SizedBox(height: 6),
                  ...grouped[section]!.map((a) => _buildToggleRow(a, isDark)),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingLG),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Iconsax.warning_2, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'Failed to load',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.paddingMD),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Iconsax.info_circle, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.isGlobal
                  ? 'These toggles are global defaults applied to every user. Individual per-user overrides still take priority over them.'
                  : 'Turn OFF any quick action you do not want this user to see on their dashboard. New users see everything by default.',
              style: AppTextStyles.bodySmall.copyWith(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title.toUpperCase(),
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.textTertiary,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildToggleRow(QuickActionPermission action, bool isDark) {
    final enabled = _isEnabled(action.key);
    final saving = _savingKeys.contains(action.key);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(action.icon, size: 15, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              action.label,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          if (saving)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: enabled,
                onChanged: (v) => _onToggle(action.key, v),
                activeThumbColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }
}
