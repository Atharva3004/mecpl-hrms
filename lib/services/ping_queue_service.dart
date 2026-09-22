import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class QueuedPing {
  final int sessionId;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final String? address;
  final int? batteryPct;
  final DateTime capturedAt;

  QueuedPing({
    required this.sessionId,
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.accuracyM,
    this.address,
    this.batteryPct,
  });

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_m': accuracyM,
        'address': address,
        'battery_pct': batteryPct,
        // Explicit offset — see ApiService.isoWithOffset.
        'captured_at': ApiService.isoWithOffset(capturedAt),
        // `is_queued` is deliberately NOT sent. The batch endpoint sets that
        // column itself, it isn't in the documented ping schema, and sending
        // an undeclared key just risks a future validation rule rejecting the
        // whole batch.
      };

  factory QueuedPing.fromJson(Map<String, dynamic> json) {
    return QueuedPing(
      sessionId: (json['session_id'] as num).toInt(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
      address: json['address'] as String?,
      batteryPct: (json['battery_pct'] as num?)?.toInt(),
      capturedAt: DateTime.parse(json['captured_at'] as String),
    );
  }
}

class PingQueueService {
  static const String _prefsKey = 'pending_pings';
  static const int _maxQueueSize = 500;
  static const int _batchMax = 100;
  static const Duration _maxAge = Duration(hours: 24);

  static final PingQueueService _instance = PingQueueService._internal();
  factory PingQueueService() => _instance;
  PingQueueService._internal();

  Future<List<QueuedPing>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => QueuedPing.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      await prefs.remove(_prefsKey);
      return [];
    }
  }

  Future<void> _saveAll(List<QueuedPing> pings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(pings.map((p) => p.toJson()).toList()),
    );
  }

  Future<int> size() async => (await _loadAll()).length;

  Future<void> enqueue(QueuedPing ping) async {
    final pings = await _loadAll();
    pings.add(ping);
    // Drop oldest if over cap.
    while (pings.length > _maxQueueSize) {
      pings.removeAt(0);
    }
    await _saveAll(pings);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Attempts to send everything in the queue using `location-ping/batch`.
  /// Returns the number of pings that were accepted by the server.
  /// Pings older than [_maxAge] are dropped silently.
  Future<int> flush(String token) async {
    final all = await _loadAll();
    if (all.isEmpty) return 0;

    final cutoff = DateTime.now().toUtc().subtract(_maxAge);
    final fresh = all.where((p) => p.capturedAt.toUtc().isAfter(cutoff)).toList();

    if (fresh.isEmpty) {
      await clear();
      return 0;
    }

    int accepted = 0;
    final remaining = <QueuedPing>[];

    // Chunk in batches of _batchMax.
    for (var i = 0; i < fresh.length; i += _batchMax) {
      final end = (i + _batchMax < fresh.length) ? i + _batchMax : fresh.length;
      final chunk = fresh.sublist(i, end);

      final response = await ApiService.flushPingBatch(
        token: token,
        pings: chunk.map((p) => p.toJson()).toList(),
      );

      if (!response.isSuccess) {
        // Network/server error — keep the rest for next attempt.
        remaining.addAll(fresh.sublist(i));
        break;
      }

      final data = response.data?['data'] as Map<String, dynamic>?;
      accepted += (data?['accepted'] as num?)?.toInt() ?? chunk.length;

      // Rejected pings are dropped — the server has confirmed those sessions
      // are gone, so retrying can't help. Log them, though: a run of
      // SESSION_NOT_ACTIVE means sessions are being closed underneath a live
      // device, and silently discarding them is how that stayed invisible.
      final errors = data?['errors'];
      if (errors is List && errors.isNotEmpty) {
        debugPrint(
          '⚠️ Ping batch: ${errors.length} of ${chunk.length} rejected — $errors',
        );
      }
    }

    if (remaining.isEmpty) {
      await clear();
    } else {
      await _saveAll(remaining);
    }
    return accepted;
  }
}
