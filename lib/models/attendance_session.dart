import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AttendanceSession {
  static const String _prefsKey = 'active_session';

  final int sessionId;
  final DateTime startedAt;
  final int pingCount;

  AttendanceSession({
    required this.sessionId,
    required this.startedAt,
    this.pingCount = 0,
  });

  AttendanceSession copyWith({int? pingCount}) => AttendanceSession(
        sessionId: sessionId,
        startedAt: startedAt,
        pingCount: pingCount ?? this.pingCount,
      );

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'started_at': startedAt.toIso8601String(),
        'ping_count': pingCount,
      };

  factory AttendanceSession.fromJson(Map<String, dynamic> json) {
    final startedRaw = json['started_at'];
    final startedAt = startedRaw is String
        ? DateTime.parse(startedRaw).toLocal()
        : DateTime.now();
    return AttendanceSession(
      sessionId: (json['session_id'] as num).toInt(),
      startedAt: startedAt,
      pingCount: (json['ping_count'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<AttendanceSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AttendanceSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      await prefs.remove(_prefsKey);
      return null;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
