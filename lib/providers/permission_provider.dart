// Permission Provider - manages per-user quick-action visibility.
// Writes are local-first (SharedPreferences) with best-effort server sync;
// this keeps the admin UI functional even before backend endpoints exist.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class PermissionProvider extends ChangeNotifier {
  // User-specific overrides for the currently logged-in user.
  Map<String, bool> _currentUserPermissions = {};
  // Global defaults that apply to everyone unless overridden per-user.
  Map<String, bool> _globalPermissions = {};
  String? _currentUserId;
  bool _isLoading = false;
  String? _error;

  Map<String, bool> get currentUserPermissions =>
      Map.unmodifiable(_currentUserPermissions);
  Map<String, bool> get globalPermissions =>
      Map.unmodifiable(_globalPermissions);
  String? get currentUserId => _currentUserId;
  bool get isLoading => _isLoading;
  String? get error => _error;

  static String _cacheKey(String userId) => 'perms_cache_$userId';
  static const String _globalCacheKey = 'perms_cache_global';

  // Resolution order: user-specific override → global default → ON (opt-out).
  bool isEnabled(String actionKey) {
    if (_currentUserPermissions.containsKey(actionKey)) {
      return _currentUserPermissions[actionKey]!;
    }
    if (_globalPermissions.containsKey(actionKey)) {
      return _globalPermissions[actionKey]!;
    }
    return true;
  }

  // Called on login / app start for the logged-in user.
  Future<void> loadForUser({
    required String userId,
    required String token,
  }) async {
    _currentUserId = userId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();

    // Read local cache first (may contain admin's edits from this device).
    Map<String, bool> localCached = {};
    final cachedStr = prefs.getString(_cacheKey(userId));
    if (cachedStr != null) {
      try {
        localCached = _parsePermissionsMap(json.decode(cachedStr));
      } catch (_) {}
    }

    final response = await ApiService.getUserPermissions(
      token: token,
      userId: userId,
    );

    if (response.isSuccess && response.data != null) {
      final parsed = _parsePermissionsMap(response.data!['permissions']);
      if (parsed.isNotEmpty) {
        // Server has authoritative data — use it and refresh the cache.
        _currentUserPermissions = parsed;
        await prefs.setString(_cacheKey(userId), json.encode(parsed));
      } else {
        // Server returned empty (e.g. endpoint not built yet). Keep local cache.
        _currentUserPermissions = localCached;
      }
    } else {
      _currentUserPermissions = localCached;
      _error = response.error;
      debugPrint(
        '[PermissionProvider] Load failed, using cache: ${response.error}',
      );
    }

    _isLoading = false;
    notifyListeners();
  }

  // Admin-only: fetch another user's permissions.
  // Tries server first; falls back to the admin's local cache for that user.
  Future<Map<String, bool>> fetchForTargetUser({
    required String targetUserId,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final response = await ApiService.getUserPermissions(
      token: token,
      userId: targetUserId,
    );
    if (response.isSuccess && response.data != null) {
      final parsed = _parsePermissionsMap(response.data!['permissions']);
      if (parsed.isNotEmpty) return parsed;
    }
    // Fallback: admin's locally stored edits for this target user.
    final cached = prefs.getString(_cacheKey(targetUserId));
    if (cached != null) {
      try {
        return _parsePermissionsMap(json.decode(cached));
      } catch (_) {}
    }
    return {};
  }

  // Admin-only: update a target user's permission.
  // Local-first: persist immediately to SharedPreferences, then attempt server sync.
  // Only rolls back if the local write itself fails.
  Future<bool> setTargetUserPermission({
    required String targetUserId,
    required String actionKey,
    required bool enabled,
    required String token,
    required Map<String, bool> localState,
    required void Function(Map<String, bool>) onStateChange,
  }) async {
    localState[actionKey] = enabled;
    onStateChange(localState);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey(targetUserId), json.encode(localState));
    } catch (e) {
      debugPrint('[PermissionProvider] Local write failed: $e');
      return false;
    }

    // Best-effort server sync — failures are logged but not surfaced.
    final response = await ApiService.updateUserPermission(
      token: token,
      userId: targetUserId,
      actionKey: actionKey,
      enabled: enabled,
    );
    if (!response.isSuccess) {
      debugPrint('[PermissionProvider] Server sync failed: ${response.error}');
    }

    // If this target user is the currently logged-in user on this device,
    // reflect the change immediately.
    if (_currentUserId == targetUserId) {
      _currentUserPermissions[actionKey] = enabled;
      notifyListeners();
    }
    return true;
  }

  // Load global defaults into memory. Local-cache-aware, like loadForUser.
  Future<void> loadGlobal({required String token}) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, bool> localCached = {};
    final cachedStr = prefs.getString(_globalCacheKey);
    if (cachedStr != null) {
      try {
        localCached = _parsePermissionsMap(json.decode(cachedStr));
      } catch (_) {}
    }

    final response = await ApiService.getGlobalPermissions(token: token);
    if (response.isSuccess && response.data != null) {
      final parsed = _parsePermissionsMap(response.data!['permissions']);
      if (parsed.isNotEmpty) {
        _globalPermissions = parsed;
        await prefs.setString(_globalCacheKey, json.encode(parsed));
      } else {
        _globalPermissions = localCached;
      }
    } else {
      _globalPermissions = localCached;
      debugPrint(
        '[PermissionProvider] Global load failed, using cache: ${response.error}',
      );
    }
    notifyListeners();
  }

  // Admin-only: fetch global defaults for editing (bypasses in-memory cache).
  Future<Map<String, bool>> fetchGlobal({required String token}) async {
    final prefs = await SharedPreferences.getInstance();
    final response = await ApiService.getGlobalPermissions(token: token);
    if (response.isSuccess && response.data != null) {
      final parsed = _parsePermissionsMap(response.data!['permissions']);
      if (parsed.isNotEmpty) return parsed;
    }
    final cached = prefs.getString(_globalCacheKey);
    if (cached != null) {
      try {
        return _parsePermissionsMap(json.decode(cached));
      } catch (_) {}
    }
    return {};
  }

  // Admin-only: update a global permission. Local-first, best-effort server sync.
  Future<bool> setGlobalPermission({
    required String actionKey,
    required bool enabled,
    required String token,
    required Map<String, bool> localState,
    required void Function(Map<String, bool>) onStateChange,
  }) async {
    localState[actionKey] = enabled;
    onStateChange(localState);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_globalCacheKey, json.encode(localState));
    } catch (e) {
      debugPrint('[PermissionProvider] Global local write failed: $e');
      return false;
    }

    final response = await ApiService.updateGlobalPermission(
      token: token,
      actionKey: actionKey,
      enabled: enabled,
    );
    if (!response.isSuccess) {
      debugPrint(
        '[PermissionProvider] Global server sync failed: ${response.error}',
      );
    }

    // Reflect the global change in memory so the current user's dashboard
    // updates immediately (unless they have a user-specific override).
    _globalPermissions[actionKey] = enabled;
    notifyListeners();
    return true;
  }

  void clear() {
    _currentUserId = null;
    _currentUserPermissions = {};
    _globalPermissions = {};
    _error = null;
    notifyListeners();
  }

  bool isCurrentUser(String userId) => _currentUserId == userId;

  Map<String, bool> _parsePermissionsMap(dynamic raw) {
    if (raw is Map) {
      return raw.map(
        (k, v) => MapEntry(k.toString(), v == true || v.toString() == 'true'),
      );
    }
    return {};
  }
}
