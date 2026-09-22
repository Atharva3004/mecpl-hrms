// http.Client wrapper that auto-attaches the bearer token and fires
// SessionManager.markExpired() on 401. Future API code should construct
// requests through this client; the legacy paths in ApiService still work
// because they call ApiService._checkAuth(response) inline.
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'session_manager.dart';

const String _kTokenPref = 'auth_token';

class AuthHttpClient extends http.BaseClient {
  AuthHttpClient({http.Client? inner}) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.headers.containsKey('Authorization')) {
      final token = await _readToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
    }

    final response = await _inner.send(request);

    if (response.statusCode == 401) {
      SessionManager.instance.markExpired(
        reason: 'Your session has expired. Please login again.',
      );
    }

    return response;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  Future<String?> _readToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kTokenPref);
    } catch (_) {
      return null;
    }
  }
}
