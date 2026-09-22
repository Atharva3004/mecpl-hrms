// Project Details Screen - Director-only entry under the Teams section.
//
// Flow (three views inside a single route):
//   home  -> two accordions: "Departments" (by function) and "Projects" (by
//            office branch).
//   tree  -> the org tree of one branch:
//            Project Head -> Project Manager -> Department -> Employees.
//   dept  -> every employee of one department, across all branches.
// Tapping a person anywhere opens a details sheet with their reporting chain.
//
// Data comes from the API: `getBranches` fills the Projects accordion and
// `getEmployeesByBranch` fills a branch's roster. The API returns a flat
// employee list, so the hierarchy is DERIVED here (see `_buildTree`).
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_colors.dart';
import '../../models/branch_model.dart';
import '../../models/role_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

// ---------------------------------------------------------------------------
// View + node models
// ---------------------------------------------------------------------------

enum _View { home, tree, dept }

enum _NodeKind { head, pm, dept, employee }

/// An employee plus the branch they were loaded from, and the reporting chain
/// resolved while the tree was built.
class _Person {
  _Person({required this.user, required this.branchName});

  final UserModel user;
  final String branchName;

  String? pmName;
  String? headName;

  String get name =>
      user.fullName.trim().isEmpty ? (user.email.split('@').first) : user.fullName;
  String get designation =>
      (user.designation?.trim().isNotEmpty ?? false)
          ? user.designation!.trim()
          : user.role.displayName;
  String get department => (user.department?.trim().isNotEmpty ?? false)
      ? user.department!.trim()
      : 'General';

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    final a = parts.isNotEmpty && parts.first.isNotEmpty ? parts.first[0] : '';
    final b = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    final out = (a + b).toUpperCase();
    return out.isEmpty ? '?' : out;
  }
}

/// One node of the derived org tree.
class _OrgNode {
  _OrgNode({
    required this.kind,
    required this.title,
    required this.key,
    this.subtitle,
    this.person,
    List<_OrgNode>? children,
  }) : children = children ?? [];

  final _NodeKind kind;
  final String title;
  final String key;
  final String? subtitle;
  final _Person? person;
  final List<_OrgNode> children;

  /// People sitting anywhere below this node (a department counts its members).
  int get headcount {
    if (kind == _NodeKind.employee) return 0;
    if (kind == _NodeKind.dept) return children.length;
    return children.fold<int>(0, (sum, c) => sum + c.headcount);
  }
}

/// A tree node flattened to a row, carrying its indentation depth.
/// When [seeMore] is set the row is the "see more" footer for [node] rather
/// than the node itself.
class _FlatRow {
  const _FlatRow(this.node, this.depth, {this.seeMore = false});
  final _OrgNode node;
  final int depth;
  final bool seeMore;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ProjectDetailsScreen extends StatefulWidget {
  const ProjectDetailsScreen({super.key});

  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen> {
  // Department accent palette — a department always gets the same colour.
  static const List<Color> _palette = [
    Color(0xFF4F46E5),
    Color(0xFFEB6834),
    Color(0xFF1BAF7A),
    Color(0xFFEDA100),
    Color(0xFFE87BA4),
    Color(0xFF0891B2),
    Color(0xFF7C3AED),
    Color(0xFFE34948),
  ];

  // --- branches (Projects accordion) ---
  List<BranchModel> _branches = [];
  bool _loadingBranches = false;
  String? _branchesError;

  // --- rosters, cached per branch id ---
  final Map<int, List<_Person>> _peopleByBranch = {};
  final Map<int, List<_OrgNode>> _treeByBranch = {};

  // --- directory across every branch (Departments accordion) ---
  final List<_Person> _directory = [];
  bool _loadingDirectory = false;
  bool _directoryLoaded = false;
  String? _directoryError;

  // --- navigation state ---
  _View _view = _View.home;
  String? _openCat; // 'dept' | 'proj' | null
  BranchModel? _branch;
  String? _deptName;
  bool _loadingTree = false;

  final Set<String> _expanded = {};
  String? _selectedKey;

  // --- search + "see more" paging ---
  // A department can hold thousands of people, so every list of employees —
  // an office card in the department view, a department node in the org tree —
  // starts at `_pageSize` names and grows on demand. Keyed by office key or
  // tree node key.
  static const int _pageSize = 5;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  final Map<String, int> _shownCounts = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBranches());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Data
  // -------------------------------------------------------------------------

  String get _token => context.read<AuthProvider>().token ?? '';

  Future<void> _loadBranches() async {
    setState(() {
      _loadingBranches = true;
      _branchesError = null;
    });
    try {
      final branches = await ApiService.getBranches(_token);
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _loadingBranches = false;
      });
      // The Departments accordion needs every branch roster; if the user
      // already opened it while branches were loading, fill it in now.
      if (_openCat == 'dept') _loadDirectory();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingBranches = false;
        _branchesError = 'Failed to load projects. Tap to retry.';
      });
    }
  }

  Future<List<_Person>> _peopleFor(BranchModel branch) async {
    final cached = _peopleByBranch[branch.id];
    if (cached != null) return cached;
    final users = await ApiService.getEmployeesByBranch(
      token: _token,
      branchId: branch.id,
    );
    final people = users
        .map((u) => _Person(user: u, branchName: branch.branchName))
        .toList();
    _peopleByBranch[branch.id] = people;
    return people;
  }

  /// Loads every branch roster once so the Departments accordion can group
  /// people by function across the whole organisation.
  Future<void> _loadDirectory() async {
    if (_directoryLoaded || _loadingDirectory) return;
    if (_branches.isEmpty) return;
    setState(() {
      _loadingDirectory = true;
      _directoryError = null;
    });
    try {
      final rosters = await Future.wait(_branches.map(_peopleFor));
      if (!mounted) return;
      setState(() {
        _directory
          ..clear()
          ..addAll(rosters.expand((r) => r));
        // Resolve the reporting chain for everyone we just pulled in.
        for (final branch in _branches) {
          _treeFor(branch);
        }
        _loadingDirectory = false;
        _directoryLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingDirectory = false;
        _directoryError = 'Could not load departments. Tap to retry.';
      });
    }
  }

  /// Departments across the org, ordered by headcount (largest first).
  List<MapEntry<String, List<_Person>>> get _departments {
    final map = <String, List<_Person>>{};
    for (final p in _directory) {
      map.putIfAbsent(p.department, () => []).add(p);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return entries;
  }

  // -------------------------------------------------------------------------
  // Hierarchy derivation
  //
  // The employees endpoint returns a flat list with no parent links, so the
  // tree is inferred from role + designation:
  //   * Project Head   -> role `director`, or a designation containing "head".
  //   * Project Manager-> role `manager`,  or a designation containing
  //                       "manager"/"lead" (heads win when both match).
  //   * everyone else  -> grouped under their department.
  // Departments attach to the manager whose own department matches; leftovers
  // are spread round-robin. With no head/manager in a branch the departments
  // simply sit at the root.
  // -------------------------------------------------------------------------

  List<_OrgNode> _treeFor(BranchModel branch) {
    final cached = _treeByBranch[branch.id];
    if (cached != null) return cached;
    final tree = _buildTree(_peopleByBranch[branch.id] ?? const []);
    _treeByBranch[branch.id] = tree;
    return tree;
  }

  bool _isHead(_Person p) {
    final d = p.designation.toLowerCase();
    return p.user.role == UserRole.director ||
        d.contains('head') ||
        d.contains('director');
  }

  bool _isManager(_Person p) {
    final d = p.designation.toLowerCase();
    return p.user.role == UserRole.manager ||
        d.contains('manager') ||
        d.contains('lead');
  }

  List<_OrgNode> _buildTree(List<_Person> people) {
    if (people.isEmpty) return [];

    final heads = people.where(_isHead).toList();
    final headSet = heads.toSet();
    final managers =
        people.where((p) => !headSet.contains(p) && _isManager(p)).toList();
    final managerSet = managers.toSet();
    final rest = people
        .where((p) => !headSet.contains(p) && !managerSet.contains(p))
        .toList();

    // Department buckets, largest first for a stable, readable order.
    final buckets = <String, List<_Person>>{};
    for (final p in rest) {
      buckets.putIfAbsent(p.department, () => []).add(p);
    }
    final deptNames = buckets.keys.toList()
      ..sort((a, b) => buckets[b]!.length.compareTo(buckets[a]!.length));

    _OrgNode deptNode(String name, _Person? pm, _Person? head) {
      final members = buckets[name]!;
      final node = _OrgNode(
        kind: _NodeKind.dept,
        title: name,
        key: 'dept:$name:${pm?.user.id ?? '-'}:${head?.user.id ?? '-'}',
        subtitle: 'Department',
      );
      for (final m in members) {
        m.pmName = pm?.name;
        m.headName = head?.name;
        node.children.add(
          _OrgNode(
            kind: _NodeKind.employee,
            title: m.name,
            subtitle: m.designation,
            key: 'emp:${m.user.id}:${m.branchName}',
            person: m,
          ),
        );
      }
      return node;
    }

    // No leadership in this branch: show the departments straight away.
    if (heads.isEmpty && managers.isEmpty) {
      return [for (final d in deptNames) deptNode(d, null, null)];
    }

    // Managers hang off heads (round-robin so no head is left empty).
    final headNodes = <_OrgNode>[];
    for (final h in heads) {
      headNodes.add(
        _OrgNode(
          kind: _NodeKind.head,
          title: h.name,
          subtitle: h.designation,
          key: 'head:${h.user.id}',
          person: h,
        ),
      );
    }

    final managerNodes = <_OrgNode>[];
    for (final m in managers) {
      final head = heads.isEmpty ? null : heads[managers.indexOf(m) % heads.length];
      m.headName = head?.name;
      final node = _OrgNode(
        kind: _NodeKind.pm,
        title: m.name,
        subtitle: m.designation,
        key: 'pm:${m.user.id}',
        person: m,
      );
      managerNodes.add(node);
      if (headNodes.isEmpty) continue;
      headNodes[managers.indexOf(m) % headNodes.length].children.add(node);
    }

    // Departments go to the manager sharing their department, else round-robin.
    final remaining = <String>[];
    for (final name in deptNames) {
      final owner = managers.where((m) => m.department == name).toList();
      if (owner.isNotEmpty && managerNodes.isNotEmpty) {
        final idx = managers.indexOf(owner.first);
        managerNodes[idx].children.add(
              deptNode(name, owner.first, _personOf(headNodes, owner.first)),
            );
      } else {
        remaining.add(name);
      }
    }
    for (var i = 0; i < remaining.length; i++) {
      final name = remaining[i];
      if (managerNodes.isNotEmpty) {
        final pmNode = managerNodes[i % managerNodes.length];
        pmNode.children.add(
          deptNode(name, pmNode.person, _personOf(headNodes, pmNode.person)),
        );
      } else if (headNodes.isNotEmpty) {
        final headNode = headNodes[i % headNodes.length];
        headNode.children.add(deptNode(name, null, headNode.person));
      }
    }

    if (headNodes.isNotEmpty) return headNodes;
    return managerNodes;
  }

  /// The head a manager was attached to, resolved back from the built nodes.
  _Person? _personOf(List<_OrgNode> headNodes, _Person? manager) {
    if (manager == null) return null;
    for (final h in headNodes) {
      if (h.children.any((c) => c.person == manager)) return h.person;
    }
    return headNodes.isEmpty ? null : headNodes.first.person;
  }

  // -------------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------------

  Future<void> _openBranch(BranchModel branch) async {
    setState(() {
      _view = _View.tree;
      _branch = branch;
      _expanded.clear();
      _shownCounts.clear();
      _selectedKey = null;
      _loadingTree = _peopleByBranch[branch.id] == null;
    });
    try {
      await _peopleFor(branch);
    } catch (_) {
      _peopleByBranch[branch.id] = [];
    }
    if (!mounted) return;
    // The tree opens fully collapsed: only the top level (Project Heads, or the
    // Managers when a branch has no head) is listed. Each level opens on tap.
    setState(() => _loadingTree = false);
  }

  void _openDepartment(String name) {
    setState(() {
      _view = _View.dept;
      _deptName = name;
      _selectedKey = null;
      _query = '';
      _searchCtrl.clear();
      _shownCounts.clear();
    });
  }

  void _goHome() {
    setState(() {
      _view = _View.home;
      _branch = null;
      _deptName = null;
      _selectedKey = null;
    });
  }

  void _toggleAll() {
    final branch = _branch;
    if (branch == null) return;
    final tree = _treeFor(branch);
    final all = <String>{};
    void walk(_OrgNode n) {
      if (n.children.isNotEmpty) all.add(n.key);
      for (final c in n.children) {
        walk(c);
      }
    }

    for (final n in tree) {
      walk(n);
    }
    setState(() {
      if (_expanded.length >= all.length) {
        _expanded.clear();
      } else {
        _expanded
          ..clear()
          ..addAll(all);
      }
    });
  }

  Color _deptColor(String name) =>
      _palette[name.hashCode.abs() % _palette.length];

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : const Color(0xFFF7F8FC);

    // Dense hierarchy screen: keep the system font scale from stretching rows
    // (names, badges and the tree's indent guides) out of shape.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: _buildScaffold(isDark, bg),
    );
  }

  Widget _buildScaffold(bool isDark, Color bg) {
    return PopScope(
      canPop: _view == _View.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: _buildAppBar(isDark),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildSubHeader(isDark),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: Offset(_view == _View.home ? -0.06 : 0.06, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(
                      '${_view.name}:${_branch?.id ?? ''}:${_deptName ?? ''}',
                    ),
                    child: _buildBody(isDark),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    switch (_view) {
      case _View.home:
        return _buildHome(isDark);
      case _View.tree:
        return _buildTreeView(isDark);
      case _View.dept:
        return _buildDeptView(isDark);
    }
  }

  // --- app bar + sub header -------------------------------------------------

  // Same shape as every other screen: flat white (dark surface) bar, chevron
  // back, Poppins 17/w600 title. Only the title text animates between views.
  PreferredSizeWidget _buildAppBar(bool isDark) {
    final title = switch (_view) {
      _View.home => 'Project Details',
      _View.tree => _branch?.branchName ?? 'Project',
      _View.dept => '${_deptName ?? ''} Department',
    };
    final fg = isDark ? Colors.white : Colors.black87;

    return AppBar(
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.chevron_left, color: fg),
        // Steps back through the views before leaving the screen.
        onPressed: () {
          if (_view == _View.home) {
            Navigator.pop(context);
          } else {
            _goHome();
          }
        },
      ),
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: Text(
          title,
          key: ValueKey(title),
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            color: fg,
            fontWeight: FontWeight.w600,
            fontSize: 15.5,
          ),
        ),
      ),
      actions: [
        if (_view == _View.tree && !_loadingTree)
          IconButton(
            tooltip: _expanded.isEmpty ? 'Expand all' : 'Collapse all',
            icon: Icon(
              _expanded.isEmpty ? Iconsax.arrow_down_1 : Iconsax.arrow_up_2,
              size: 18,
              color: fg,
            ),
            onPressed: _toggleAll,
          ),
      ],
    );
  }

  /// Breadcrumb plus, on the tree/department views, the stat pills. Hidden on
  /// the home view where the crumb would only repeat the app bar title.
  Widget _buildSubHeader(bool isDark) {
    if (_view == _View.home) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 11),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : const Color(0xFFEDEFF5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCrumb(isDark),
          if (_view == _View.tree) ...[
            const SizedBox(height: 10),
            _buildTreeStats(isDark),
          ],
          if (_view == _View.dept) ...[
            const SizedBox(height: 10),
            _buildDeptStats(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildCrumb(bool isDark) {
    final parts = <String>[
      'Organisation',
      if (_view == _View.tree) 'Projects',
      if (_view == _View.dept) 'Departments',
      if (_view == _View.tree) _branch?.branchName ?? '',
      if (_view == _View.dept) _deptName ?? '',
    ].where((p) => p.isNotEmpty).toList();

    final muted =
        isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: Row(
        key: ValueKey(parts.join('/')),
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Icon(Icons.chevron_right, size: 12, color: muted),
              ),
            Flexible(
              child: Text(
                parts[i],
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: i == parts.length - 1
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: i == parts.length - 1 ? AppColors.primary : muted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTreeStats(bool isDark) {
    final people = _branch == null
        ? const <_Person>[]
        : (_peopleByBranch[_branch!.id] ?? const <_Person>[]);
    final depts = people.map((p) => p.department).toSet().length;
    final leads = people.where((p) => _isHead(p) || _isManager(p)).length;
    return Row(
      children: [
        _statPill(isDark, Iconsax.people, people.length, 'People',
            AppColors.primary),
        const SizedBox(width: 8),
        _statPill(isDark, Iconsax.buildings_2, depts, 'Departments',
            AppColors.secondaryDark),
        const SizedBox(width: 8),
        _statPill(isDark, Iconsax.user_octagon, leads, 'Leads',
            AppColors.directorColor),
      ],
    );
  }

  Widget _buildDeptStats(bool isDark) {
    final people =
        _directory.where((p) => p.department == _deptName).toList();
    final offices = people.map((p) => p.branchName).toSet().length;
    final accent = _deptColor(_deptName ?? '');
    return Row(
      children: [
        _statPill(isDark, Iconsax.people, people.length, 'Members', accent),
        const SizedBox(width: 8),
        _statPill(isDark, Iconsax.location, offices, 'Offices',
            AppColors.primary),
      ],
    );
  }

  Widget _statPill(
    bool isDark,
    IconData icon,
    int value,
    String label,
    Color accent,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: isDark ? 0.16 : 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: value.toDouble()),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => Text(
                      v.round().toString(),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary,
                        height: 1.1,
                      ),
                    ),
                  ),
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 8.5,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.3, end: 0);
  }

  // --- home view ------------------------------------------------------------

  Widget _buildHome(bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 30),
      children: [
        _accordion(
          isDark: isDark,
          id: 'dept',
          icon: Iconsax.buildings_2,
          title: 'Departments',
          subtitle: _directoryLoaded
              ? '${_departments.length} departments · view by function'
              : 'View people by function',
          child: _buildDeptRows(isDark),
        ),
        const SizedBox(height: 12),
        _accordion(
          isDark: isDark,
          id: 'proj',
          icon: Iconsax.location,
          title: 'Projects',
          subtitle: _branches.isEmpty
              ? 'View people by office'
              : '${_branches.length} branches · view by office',
          child: _buildBranchRows(isDark),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            'Tap a dropdown to expand, then pick a branch or department.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
            ),
          ),
        ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
      ],
    );
  }

  Widget _accordion({
    required bool isDark,
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final open = _openCat == id;
    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFE8EAF2);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: open ? AppColors.primary.withValues(alpha: 0.45) : border,
          width: open ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: open
                ? AppColors.primary.withValues(alpha: isDark ? 0.20 : 0.14)
                : Colors.black.withValues(alpha: isDark ? 0.30 : 0.05),
            blurRadius: open ? 22 : 10,
            offset: Offset(0, open ? 10 : 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() => _openCat = open ? null : id);
                if (!open && id == 'dept') _loadDirectory();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: open ? AppColors.primaryGradient : null,
                        color: open
                            ? null
                            : AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        icon,
                        size: 19,
                        color: open ? Colors.white : AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutBack,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: open
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.textTertiary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.topCenter,
              heightFactor: open ? 1 : 0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: open ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.06, end: 0);
  }

  Widget _buildBranchRows(bool isDark) {
    if (_loadingBranches) return _shimmerRows(isDark, 3);
    if (_branchesError != null) {
      return _inlineError(isDark, _branchesError!, _loadBranches);
    }
    if (_branches.isEmpty) {
      return _inlineEmpty(isDark, 'No projects available');
    }
    return Column(
      children: [
        for (var i = 0; i < _branches.length; i++)
          _listRow(
            isDark: isDark,
            index: i,
            leading: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Iconsax.location,
                  size: 15, color: AppColors.primary),
            ),
            title: _branches[i].branchName,
            titleHighlight: AppColors.primary,
            subtitle: _peopleByBranch[_branches[i].id] != null
                ? '${_peopleByBranch[_branches[i].id]!.length} employees'
                : 'Tap to open the org tree',
            onTap: () => _openBranch(_branches[i]),
          ),
      ],
    );
  }

  Widget _buildDeptRows(bool isDark) {
    if (_loadingDirectory || _loadingBranches) return _shimmerRows(isDark, 4);
    if (_directoryError != null) {
      return _inlineError(isDark, _directoryError!, () {
        _directoryLoaded = false;
        _loadDirectory();
      });
    }
    final depts = _departments;
    if (depts.isEmpty) {
      return _inlineEmpty(isDark, 'No departments found');
    }
    return Column(
      children: [
        for (var i = 0; i < depts.length; i++)
          _listRow(
            isDark: isDark,
            index: i,
            leading: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _deptColor(depts[i].key),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: _deptColor(depts[i].key).withValues(alpha: 0.5),
                      blurRadius: 7,
                    ),
                  ],
                ),
              ),
            ),
            title: depts[i].key,
            titleHighlight: _deptColor(depts[i].key),
            subtitle:
                '${depts[i].value.map((p) => p.branchName).toSet().length} office(s)',
            trailing: _countChip(isDark, depts[i].value.length),
            onTap: () => _openDepartment(depts[i].key),
          ),
      ],
    );
  }

  Widget _listRow({
    required bool isDark,
    required int index,
    required Widget leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
    Color? titleHighlight,
  }) {
    final line = isDark ? AppColors.darkBorder : const Color(0xFFEFF1F6);
    final titleText = Text(
      title,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(
        fontSize: 11.5,
        fontWeight: titleHighlight == null ? FontWeight.w600 : FontWeight.w700,
        color: titleHighlight ??
            (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.primary.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: line)),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Department / project names sit on a tinted pill so they
                    // read as headings against the plain employee rows.
                    if (titleHighlight == null)
                      titleText
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: titleHighlight.withValues(
                              alpha: isDark ? 0.20 : 0.10),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: titleHighlight.withValues(alpha: 0.22),
                          ),
                        ),
                        child: titleText,
                      ),
                    if (titleHighlight != null) const SizedBox(height: 2),
                    Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[trailing, const SizedBox(width: 6)],
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    )
        .animate(delay: (index * 45).ms)
        .fadeIn(duration: 260.ms)
        .slideX(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _countChip(bool isDark, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant
            : AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: GoogleFonts.inter(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: isDark ? AppColors.darkTextSecondary : AppColors.primary,
        ),
      ),
    );
  }

  // --- tree view ------------------------------------------------------------

  Widget _buildTreeView(bool isDark) {
    if (_loadingTree) return _treeShimmer(isDark);

    final branch = _branch;
    if (branch == null) return const SizedBox.shrink();
    final tree = _treeFor(branch);
    if (tree.isEmpty) {
      return _emptyState(
        isDark,
        Iconsax.people,
        'No employees found',
        'This project has no staff mapped yet.',
      );
    }

    final rows = <_FlatRow>[];
    void flatten(_OrgNode node, int depth) {
      rows.add(_FlatRow(node, depth));
      if (!_expanded.contains(node.key)) return;
      final kids = node.children;
      // Departments can hold hundreds of people: show `_pageSize` at a time.
      final paged = node.kind == _NodeKind.dept;
      final shown = paged
          ? (_shownCounts[node.key] ?? _pageSize).clamp(0, kids.length)
          : kids.length;
      for (var i = 0; i < shown; i++) {
        flatten(kids[i], depth + 1);
      }
      if (paged && (kids.length > shown || shown > _pageSize)) {
        rows.add(_FlatRow(node, depth + 1, seeMore: true));
      }
    }

    for (final n in tree) {
      flatten(n, 0);
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 34),
      itemCount: rows.length,
      itemBuilder: (context, i) => _treeRow(isDark, rows[i], i),
    );
  }

  Widget _treeRow(bool isDark, _FlatRow row, int index) {
    if (row.seeMore) return _treeSeeMoreRow(isDark, row);
    final node = row.node;
    final hasChildren = node.children.isNotEmpty;
    final open = _expanded.contains(node.key);
    final selected = _selectedKey == node.key;
    final line = isDark ? AppColors.darkBorder : const Color(0xFFE4E7EF);

    final accent = switch (node.kind) {
      _NodeKind.head => AppColors.directorColor,
      _NodeKind.pm => AppColors.managerColor,
      _NodeKind.dept => _deptColor(node.title),
      _NodeKind.employee => _deptColor(node.person?.department ?? node.title),
    };

    Widget marker;
    switch (node.kind) {
      case _NodeKind.dept:
        marker = Container(
          width: 26,
          alignment: Alignment.center,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(3.5),
              boxShadow: [
                BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 6),
              ],
            ),
          ),
        );
      case _NodeKind.employee:
        marker = _avatar(node.person!, size: 28, color: accent, filled: true);
      case _NodeKind.pm:
        marker = _avatar(node.person!, size: 32, color: accent, filled: false);
      case _NodeKind.head:
        marker = _avatar(node.person!, size: 34, color: accent, filled: true);
    }

    final tag = switch (node.kind) {
      _NodeKind.head => 'PH',
      _NodeKind.pm => 'PM',
      _ => null,
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var d = 0; d < row.depth; d++)
            Container(
              width: 16,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: line)),
              ),
            ),
          Expanded(
            child: Material(
              // Department rows keep a tinted background so they stand out as
              // group headings inside the tree.
              color: selected
                  ? AppColors.primary.withValues(alpha: isDark ? 0.16 : 0.07)
                  : (node.kind == _NodeKind.dept
                      ? accent.withValues(alpha: isDark ? 0.16 : 0.08)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(13),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  if (node.kind == _NodeKind.employee) {
                    setState(() => _selectedKey = node.key);
                    _showPersonSheet(node.person!);
                    return;
                  }
                  setState(() {
                    _selectedKey = node.key;
                    if (open) {
                      _expanded.remove(node.key);
                    } else {
                      _expanded.add(node.key);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 7, 10, 7),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        child: hasChildren
                            ? AnimatedRotation(
                                turns: open ? 0.25 : 0,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  size: 13,
                                  color: isDark
                                      ? AppColors.darkTextTertiary
                                      : AppColors.textTertiary,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      marker,
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    node.title,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontWeight: node.kind == _NodeKind.employee
                                          ? FontWeight.w600
                                          : FontWeight.w700,
                                      color: isDark
                                          ? AppColors.darkTextPrimary
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (tag != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      tag,
                                      style: GoogleFonts.inter(
                                        fontSize: 7.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                        color: accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (node.subtitle != null)
                              Text(
                                node.subtitle!,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  color: isDark
                                      ? AppColors.darkTextTertiary
                                      : AppColors.textTertiary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (node.kind == _NodeKind.employee)
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 17,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.textTertiary,
                        )
                      else
                        _countChip(isDark, node.headcount),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    )
        .animate(key: ValueKey(node.key))
        .fadeIn(duration: 240.ms, delay: (index.clamp(0, 12) * 22).ms)
        .slideX(begin: 0.05, end: 0, curve: Curves.easeOutCubic);
  }

  /// "See more" / "Show less" row under a paged department node in the tree.
  Widget _treeSeeMoreRow(bool isDark, _FlatRow row) {
    final node = row.node;
    final total = node.children.length;
    final shown = (_shownCounts[node.key] ?? _pageSize).clamp(0, total);
    final remaining = total - shown;
    final next = remaining >= _pageSize ? _pageSize : remaining;
    final line = isDark ? AppColors.darkBorder : const Color(0xFFE4E7EF);
    final accent = _deptColor(node.title);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var d = 0; d < row.depth; d++)
            Container(
              width: 16,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: line)),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 22, top: 2, bottom: 4),
              child: Row(
                children: [
                  if (remaining > 0)
                    _treeSeeMoreChip(
                      label: 'See $next more',
                      hint: '$remaining left',
                      color: accent,
                      isDark: isDark,
                      onTap: () => setState(
                        () => _shownCounts[node.key] = shown + _pageSize,
                      ),
                      icon: Icons.keyboard_arrow_down_rounded,
                    ),
                  if (remaining > 0 && shown > _pageSize)
                    const SizedBox(width: 8),
                  if (shown > _pageSize)
                    _treeSeeMoreChip(
                      label: 'Show less',
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                      isDark: isDark,
                      onTap: () =>
                          setState(() => _shownCounts[node.key] = _pageSize),
                      icon: Icons.keyboard_arrow_up_rounded,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate(key: ValueKey('more:${node.key}')).fadeIn(duration: 240.ms);
  }

  Widget _treeSeeMoreChip({
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
    required IconData icon,
    String? hint,
  }) {
    return Material(
      color: color.withValues(alpha: isDark ? 0.16 : 0.08),
      borderRadius: BorderRadius.circular(9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: 5),
                Text(
                  '· $hint',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    color: isDark
                        ? AppColors.darkTextTertiary
                        : AppColors.textTertiary,
                  ),
                ),
              ],
              const SizedBox(width: 2),
              Icon(icon, size: 15, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(
    _Person person, {
    required double size,
    required Color color,
    required bool filled,
  }) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: filled
            ? LinearGradient(
                colors: [color, Color.lerp(color, Colors.black, 0.22)!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: filled ? null : color.withValues(alpha: 0.10),
        border: filled ? null : Border.all(color: color, width: 1.4),
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Text(
        person.initials,
        style: GoogleFonts.inter(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
          color: filled ? Colors.white : color,
        ),
      ),
    );
  }

  // --- department view ------------------------------------------------------

  Widget _buildDeptView(bool isDark) {
    final all = _directory.where((p) => p.department == _deptName).toList();

    if (all.isEmpty) {
      return _emptyState(
        isDark,
        Iconsax.buildings_2,
        'Nobody here yet',
        'No employees are mapped to ${_deptName ?? 'this department'}.',
      );
    }

    final q = _query.trim().toLowerCase();
    final people =
        (q.isEmpty
            ? all
            : all
                  .where(
                    (p) =>
                        p.name.toLowerCase().contains(q) ||
                        p.designation.toLowerCase().contains(q) ||
                        p.branchName.toLowerCase().contains(q),
                  )
                  .toList())
          ..sort((a, b) => a.name.compareTo(b.name));

    // Group by office so the roster reads branch by branch.
    final byBranch = <String, List<_Person>>{};
    for (final p in people) {
      byBranch.putIfAbsent(p.branchName, () => []).add(p);
    }
    final branchNames = byBranch.keys.toList()..sort();

    return Column(
      children: [
        _buildSearchField(
          isDark,
          hint: 'Search name, designation or office…',
          resultLabel: q.isEmpty
              ? null
              : '${people.length} match${people.length == 1 ? '' : 'es'} in ${branchNames.length} office${branchNames.length == 1 ? '' : 's'}',
        ),
        Expanded(
          child: people.isEmpty
              ? _emptyState(
                  isDark,
                  Iconsax.search_normal,
                  'No match for "${_query.trim()}"',
                  'Try a different name, designation or office.',
                )
              : _buildDeptList(isDark, branchNames, byBranch),
        ),
      ],
    );
  }

  Widget _buildDeptList(
    bool isDark,
    List<String> branchNames,
    Map<String, List<_Person>> byBranch,
  ) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 34),
      itemCount: branchNames.length,
      itemBuilder: (context, i) {
        final branchName = branchNames[i];
        final members = byBranch[branchName]!;
        // Only `_pageSize` names per office until "See more" is tapped.
        final officeKey = '${_deptName ?? ''}|$branchName';
        final shown =
            (_shownCounts[officeKey] ?? _pageSize).clamp(0, members.length);
        final remaining = members.length - shown;
        final accent = _deptColor(_deptName ?? '');
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : const Color(0xFFE8EAF2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Office (project) name sits on a tinted band so it reads as the
              // card's heading rather than another employee row.
              Container(
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.09),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(17),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: accent.withValues(alpha: 0.22),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Iconsax.location, size: 14, color: accent),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        branchName,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _countChip(isDark, members.length),
                  ],
                ),
              ),
              for (var j = 0; j < shown; j++)
                _listRow(
                  isDark: isDark,
                  index: j % _pageSize,
                  leading: _avatar(
                    members[j],
                    size: 30,
                    color: _deptColor(members[j].department),
                    filled: true,
                  ),
                  title: members[j].name,
                  subtitle: members[j].designation,
                  onTap: () => _showPersonSheet(members[j]),
                ),
              if (remaining > 0 || shown > _pageSize)
                _buildSeeMore(
                  isDark: isDark,
                  officeKey: officeKey,
                  shown: shown,
                  total: members.length,
                ),
            ],
          ),
        )
            .animate(delay: (i.clamp(0, 8) * 60).ms)
            .fadeIn(duration: 300.ms)
            .slideY(begin: 0.06, end: 0);
      },
    );
  }

  /// "See more" / "Show less" footer for one office card.
  Widget _buildSeeMore({
    required bool isDark,
    required String officeKey,
    required int shown,
    required int total,
  }) {
    final remaining = total - shown;
    final line = isDark ? AppColors.darkBorder : const Color(0xFFEFF1F6);
    final next = remaining >= _pageSize ? _pageSize : remaining;

    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: line))),
      child: Row(
        children: [
          if (remaining > 0)
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(
                    () => _shownCounts[officeKey] = shown + _pageSize,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'See $next more',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '· $remaining left',
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 17,
                          color: AppColors.primary,
                        )
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .moveY(begin: -1.5, end: 1.5, duration: 900.ms),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (remaining > 0 && shown > _pageSize)
            Container(width: 1, height: 22, color: line),
          if (shown > _pageSize)
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () =>
                      setState(() => _shownCounts[officeKey] = _pageSize),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Text(
                      'Show less',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Search box shown above the department roster.
  Widget _buildSearchField(
    bool isDark, {
    required String hint,
    String? resultLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() {
              _query = v;
              // A new result set restarts every office at the first page.
              _shownCounts.clear();
            }),
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                fontSize: 11.5,
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.textTertiary,
              ),
              prefixIcon: const Icon(
                Iconsax.search_normal,
                size: 16,
                color: AppColors.primary,
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.textTertiary,
                      ),
                      onPressed: () => setState(() {
                        _query = '';
                        _searchCtrl.clear();
                        _shownCounts.clear();
                      }),
                    ),
              isDense: true,
              filled: true,
              fillColor: isDark ? AppColors.darkSurface : Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? AppColors.darkBorder : const Color(0xFFE8EAF2),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? AppColors.darkBorder : const Color(0xFFE8EAF2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: resultLabel == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(4, 7, 0, 0),
                    child: Text(
                      resultLabel,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.08, end: 0);
  }

  // --- person sheet ---------------------------------------------------------

  void _showPersonSheet(_Person person) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _deptColor(person.department);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 10,
          bottom: 22 + MediaQuery.of(ctx).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkBorder : const Color(0xFFDDE1EA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _avatar(person, size: 54, color: accent, filled: true)
                    .animate()
                    .scale(
                      begin: const Offset(0.6, 0.6),
                      end: const Offset(1, 1),
                      duration: 380.ms,
                      curve: Curves.easeOutBack,
                    ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        person.designation,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.15, end: 0),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _fact(isDark, 'Employee ID',
                      person.user.employeeId ?? person.user.id),
                ),
                const SizedBox(width: 9),
                Expanded(child: _fact(isDark, 'Branch', person.branchName)),
              ],
            ).animate(delay: 80.ms).fadeIn(duration: 300.ms).slideY(begin: 0.15, end: 0),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(child: _fact(isDark, 'Department', person.department)),
                const SizedBox(width: 9),
                Expanded(child: _fact(isDark, 'Role', person.user.role.displayName)),
              ],
            ).animate(delay: 140.ms).fadeIn(duration: 300.ms).slideY(begin: 0.15, end: 0),
            if ((person.user.email).isNotEmpty ||
                (person.user.phone?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 9),
              Row(
                children: [
                  if (person.user.email.isNotEmpty)
                    Expanded(child: _fact(isDark, 'Email', person.user.email)),
                  if (person.user.email.isNotEmpty &&
                      (person.user.phone?.isNotEmpty ?? false))
                    const SizedBox(width: 9),
                  if (person.user.phone?.isNotEmpty ?? false)
                    Expanded(child: _fact(isDark, 'Phone', person.user.phone!)),
                ],
              ).animate(delay: 200.ms).fadeIn(duration: 300.ms).slideY(begin: 0.15, end: 0),
            ],
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.14 : 0.07),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REPORTING CHAIN',
                    style: GoogleFonts.inter(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _chainLine(isDark, Iconsax.user_octagon, 'Reports to',
                      person.pmName ?? '—', 'Project Manager'),
                  const SizedBox(height: 6),
                  _chainLine(isDark, Iconsax.crown_1, 'Under',
                      person.headName ?? '—', 'Project Head'),
                  const SizedBox(height: 6),
                  _chainLine(isDark, Iconsax.location, 'Branch',
                      person.branchName, 'Office'),
                ],
              ),
            ).animate(delay: 260.ms).fadeIn(duration: 320.ms).slideY(begin: 0.2, end: 0),
          ],
        ),
      ),
    );
  }

  Widget _fact(bool isDark, String label, String value) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFEAECF3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value.isEmpty ? '—' : value,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chainLine(
    bool isDark,
    IconData icon,
    String label,
    String value,
    String role,
  ) {
    return Row(
      children: [
        Icon(icon,
            size: 13,
            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          '$label ',
          style: GoogleFonts.inter(
            fontSize: 10.5,
            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
        ),
        Text(
          role,
          style: GoogleFonts.inter(
            fontSize: 9,
            color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }

  // --- shared states --------------------------------------------------------

  Widget _shimmerRows(bool isDark, int count) {
    return Shimmer.fromColors(
      baseColor: isDark ? AppColors.darkSurfaceVariant : const Color(0xFFEEF0F5),
      highlightColor: isDark ? AppColors.darkBorder : const Color(0xFFF8F9FC),
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Container(
                      height: 11,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _treeShimmer(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
      child: Shimmer.fromColors(
        baseColor: isDark ? AppColors.darkSurfaceVariant : const Color(0xFFEEF0F5),
        highlightColor: isDark ? AppColors.darkBorder : const Color(0xFFF8F9FC),
        child: Column(
          children: [
            for (var i = 0; i < 8; i++)
              Padding(
                padding: EdgeInsets.fromLTRB((i % 4) * 16, 7, 0, 7),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
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

  Widget _inlineError(bool isDark, String message, VoidCallback onRetry) {
    return InkWell(
      onTap: onRetry,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Row(
          children: [
            Icon(Iconsax.refresh, size: 15, color: AppColors.error),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inlineEmpty(bool isDark, String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      child: Text(
        message,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _emptyState(
    bool isDark,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: AppColors.primary),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.06, 1.06),
                duration: 1600.ms,
                curve: Curves.easeInOut,
              ),
          const SizedBox(height: 14),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms);
  }
}
