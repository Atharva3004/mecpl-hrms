// Session expiry signaling for the global 401 handler.
//
// Any code path that observes a 401 from the backend (`AuthHttpClient` or
// `ApiService._checkAuth`) calls `SessionManager.instance.markExpired()`.
// `main.dart` listens on the notifier and tells `AuthProvider` to clear the
// session + show a snackbar. The widget tree then swaps to LoginScreen via
// the existing auth-state-driven routing.
import 'package:flutter/foundation.dart';

class SessionExpiry {
  final DateTime at;
  final String? reason;
  const SessionExpiry({required this.at, this.reason});
}

class SessionManager {
  SessionManager._();
  static final SessionManager instance = SessionManager._();

  // Listened to by main.dart. Bumped each time a 401 is observed so repeat
  // expirations still notify (a plain bool would dedupe to the same value).
  final ValueNotifier<SessionExpiry?> sessionExpired = ValueNotifier(null);

  void markExpired({String? reason}) {
    sessionExpired.value = SessionExpiry(at: DateTime.now(), reason: reason);
  }

  void reset() {
    sessionExpired.value = null;
  }
}
