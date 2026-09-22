// Models for the pending manpower requisitions API (`/pending-requisitions`).
//
// The API groups requisitions per project and includes a top-level `stats`
// block. Here we flatten the groups into a single [RequisitionItem] list (each
// carrying its project + branch id) so the summary screen can group/search
// them however it likes, and expose the [RequisitionStats] separately.

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Top-level `stats` block returned alongside the requisition list.
class RequisitionStats {
  final int totalRequisitions;
  final int completed;
  final int closureCount;
  final int pendingBalance;

  const RequisitionStats({
    this.totalRequisitions = 0,
    this.completed = 0,
    this.closureCount = 0,
    this.pendingBalance = 0,
  });

  static const empty = RequisitionStats();

  factory RequisitionStats.fromJson(Map<String, dynamic> json) {
    int i(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
    return RequisitionStats(
      totalRequisitions: i(json['total_requisitions']),
      completed: i(json['completed']),
      closureCount: i(json['closure_count']),
      pendingBalance: i(json['pending_balance']),
    );
  }
}

/// A single pending requisition row (flattened with its project + branch id).
class RequisitionItem {
  final int id;
  final String project;
  final int branchId;
  final String designation; // '' when the API sends null
  final String department; // '' when the API sends null
  final int existing;
  final int required;
  final int postClosed;
  final int closureCount;
  final int balance;
  final String requisitionType; // "New Hiring" / "Replacement"
  final DateTime? reqBy;
  final String? remarks; // req_update_remarks (often the "replaced with" note)
  final String status;

  const RequisitionItem({
    required this.id,
    required this.project,
    required this.branchId,
    required this.designation,
    required this.department,
    required this.existing,
    required this.required,
    required this.postClosed,
    required this.closureCount,
    required this.balance,
    required this.requisitionType,
    required this.reqBy,
    required this.remarks,
    required this.status,
  });

  /// Card title: the real designation when present, otherwise a stable
  /// fallback built from the requisition type + id (designation is currently
  /// null across the API response).
  String get title =>
      designation.isNotEmpty ? designation : '$requisitionType · #$id';

  static final _reqByFormat = DateFormat('dd-MM-yyyy');

  factory RequisitionItem.fromJson(
    Map<String, dynamic> json, {
    required String project,
    required int branchId,
  }) {
    int i(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
    String s(dynamic v) => (v ?? '').toString().trim();

    DateTime? parseDate(dynamic v) {
      final raw = s(v);
      if (raw.isEmpty) return null;
      try {
        return _reqByFormat.parseStrict(raw);
      } catch (_) {
        return DateTime.tryParse(raw);
      }
    }

    final remarks = s(json['req_update_remarks']);

    return RequisitionItem(
      id: i(json['id']),
      project: project,
      branchId: branchId,
      designation: s(json['designation']),
      department: s(json['department']),
      existing: i(json['existing']),
      required: i(json['required']),
      postClosed: i(json['post_closed']),
      closureCount: i(json['closure_count']),
      balance: i(json['balance']),
      requisitionType: s(json['requisition_type']).isEmpty
          ? 'New Hiring'
          : s(json['requisition_type']),
      reqBy: parseDate(json['req_by']),
      remarks: remarks.isEmpty ? null : remarks,
      status: s(json['status']),
    );
  }
}

/// Result wrapper for [ApiService.getPendingRequisitions] — the flattened
/// requisition list plus the summary stats and pagination info.
class PendingRequisitionsResult {
  final RequisitionStats stats;
  final List<RequisitionItem> items;
  final int lastPage; // total pages available (from `pagination.last_page`)

  const PendingRequisitionsResult({
    required this.stats,
    required this.items,
    this.lastPage = 1,
  });

  static const empty = PendingRequisitionsResult(
    stats: RequisitionStats.empty,
    items: [],
  );

  /// Parses one page of the `/pending-requisitions` response body. The caller
  /// follows [lastPage] to fetch and merge the remaining pages.
  factory PendingRequisitionsResult.fromResponse(Map<String, dynamic> decoded) {
    final statsJson = decoded['stats'];
    final stats = statsJson is Map
        ? RequisitionStats.fromJson(Map<String, dynamic>.from(statsJson))
        : RequisitionStats.empty;

    final pagination = decoded['pagination'];
    final lastPage = pagination is Map
        ? (pagination['last_page'] is int
              ? pagination['last_page'] as int
              : int.tryParse('${pagination['last_page'] ?? ''}') ?? 1)
        : 1;

    final items = <RequisitionItem>[];
    final data = decoded['data'];
    if (data is List) {
      for (final branch in data) {
        if (branch is! Map) continue;
        final project = (branch['project'] ?? '').toString().trim();
        final branchId = branch['branch_id'] is int
            ? branch['branch_id'] as int
            : int.tryParse('${branch['branch_id'] ?? ''}') ?? 0;
        final reqs = branch['requisitions'];
        if (reqs is! List) continue;
        for (final r in reqs) {
          if (r is Map<String, dynamic>) {
            try {
              items.add(
                RequisitionItem.fromJson(
                  r,
                  project: project,
                  branchId: branchId,
                ),
              );
            } catch (e) {
              debugPrint('⚠️ Error parsing requisition item: $e');
            }
          }
        }
      }
    }
    return PendingRequisitionsResult(
      stats: stats,
      items: items,
      lastPage: lastPage,
    );
  }
}
