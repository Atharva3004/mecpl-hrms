import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/role_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

/// Admin-only live snapshot of every open attendance session.
/// Polls `GET /attendance/live` every 30 seconds.
class LiveAttendanceScreen extends StatefulWidget {
  const LiveAttendanceScreen({super.key});

  @override
  State<LiveAttendanceScreen> createState() => _LiveAttendanceScreenState();
}

class _LiveAttendanceScreenState extends State<LiveAttendanceScreen> {
  static const Duration _pollInterval = Duration(seconds: 30);

  Timer? _pollTimer;
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  String? _error;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _pollTimer = Timer.periodic(_pollInterval, (_) => _refresh(silent: true));
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Not signed in';
      });
      return;
    }

    if (!silent) setState(() => _loading = true);

    final response = await ApiService.getLiveAttendance(token: token);
    if (!mounted) return;

    if (!response.isSuccess) {
      setState(() {
        _loading = false;
        _error = response.error ?? 'Failed to load live attendance';
      });
      return;
    }

    final raw = response.data;
    final payload = (raw?['data']);
    final list = payload is List
        ? payload
            .whereType<Map<String, dynamic>>()
            .toList(growable: false)
        : const <Map<String, dynamic>>[];

    setState(() {
      _sessions = list;
      _loading = false;
      _error = null;
      _lastUpdated = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Client-side guard — backend still enforces the policy.
    final role = context.watch<AuthProvider>().currentUser?.role;
    if (role != UserRole.admin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live Attendance')),
        body: const Center(child: Text('Admins only')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.refresh),
            onPressed: _loading ? null : () => _refresh(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Iconsax.warning_2, size: 42, color: Colors.orange),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => _refresh(), child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _sessions.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('No active sessions right now')),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _sessions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _buildSessionTile(_sessions[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final count = _sessions.length;
    final updated = _lastUpdated == null
        ? '—'
        : DateFormat('HH:mm:ss').format(_lastUpdated!);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.primary.withAlpha(30),
      child: Row(
        children: [
          const Icon(Iconsax.user_tick),
          const SizedBox(width: 8),
          Text('$count active'),
          const Spacer(),
          Text('Updated $updated',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildSessionTile(Map<String, dynamic> s) {
    final employee = (s['employee'] as Map?)?.cast<String, dynamic>() ?? const {};
    final branch = (s['branch'] as Map?)?.cast<String, dynamic>() ?? const {};
    final lastPing = (s['last_ping'] as Map?)?.cast<String, dynamic>();

    // Server names these `emp_name` / `branch_name`
    // (docs/geofence-module-guide.md §3.9). Reading a bare `name` matched
    // nothing, so every row on this dashboard rendered as "—".
    final name = (employee['emp_name'] ?? employee['name'] ?? '—').toString();
    final empCode = (employee['emp_code'] ?? '').toString();
    final branchName =
        (branch['branch_name'] ?? branch['name'] ?? '—').toString();
    final pingCount = (s['ping_count'] as num?)?.toInt() ?? 0;

    final startedRaw = s['started_at']?.toString();
    final started = startedRaw != null
        ? _formatTime(DateTime.tryParse(startedRaw)?.toLocal())
        : '—';

    final insideFence = lastPing?['inside_geofence'] == true;
    final lastPingAgo = _formatAgo(
      lastPing?['captured_at']?.toString() != null
          ? DateTime.tryParse(lastPing!['captured_at'].toString())?.toLocal()
          : null,
    );
    final lat = lastPing?['latitude'];
    final lng = lastPing?['longitude'];

    return ListTile(
      isThreeLine: true,
      leading: CircleAvatar(
        backgroundColor: insideFence ? Colors.green.shade100 : Colors.orange.shade100,
        child: Icon(
          insideFence ? Iconsax.tick_circle : Iconsax.warning_2,
          color: insideFence ? Colors.green : Colors.orange,
        ),
      ),
      title: Text(
        empCode.isEmpty ? name : '$name ($empCode)',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$branchName • Started $started • Pings: $pingCount'),
          if (lastPing != null)
            Text(
              'Last: ${lat ?? '—'}, ${lng ?? '—'} ($lastPingAgo)',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
        ],
      ),
      trailing: insideFence
          ? null
          : const Text('Outside',
              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
      onTap: () {
        // Timeline drill-in deferred to a later phase (spec §5.4).
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timeline view coming soon')),
        );
      },
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('HH:mm').format(dt);
  }

  String _formatAgo(DateTime? dt) {
    if (dt == null) return 'unknown';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays}d ago';
  }
}
