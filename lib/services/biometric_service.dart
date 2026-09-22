// Biometric / Face ID service — thin wrapper around `local_auth`.
//
// Used by the app-launch unlock flow (see BiometricLockScreen). The app
// authenticates the user against the OS-managed biometric (fingerprint,
// Face ID, Face Unlock) or device PIN fallback, and the AuthProvider then
// restores the stored session.
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  /// True when the device has biometric hardware AND the OS reports we can
  /// check it right now (e.g. user has enrolled a fingerprint / face).
  /// Returns false on web, emulators without biometric, or when the user has
  /// disabled biometric in device settings.
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      return canCheck;
    } on PlatformException {
      return false;
    }
  }

  /// Lists which specific biometric factors are enrolled (fingerprint / face
  /// / iris). Used to customize the prompt copy (e.g. "Use Face ID to unlock"
  /// vs "Use fingerprint to unlock").
  Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return const <BiometricType>[];
    }
  }

  /// Shows the OS biometric prompt. Returns true on success, false if the
  /// user cancelled, failed too many times, or the device is misconfigured.
  ///
  /// `reason` is the string shown on iOS below the Face ID icon. On Android
  /// it maps to the subtitle of the biometric dialog.
  Future<bool> authenticate({
    String reason = 'Unlock MECPL HRMS',
  }) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // biometricOnly=false lets the user fall back to device PIN /
          // pattern / passcode after repeated biometric failure.
          biometricOnly: false,
          // Keep the prompt alive if the app is briefly backgrounded (e.g.
          // when the OS overlay animates in).
          stickyAuth: true,
        ),
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'MECPL HRMS',
            biometricHint: '',
            cancelButton: 'Cancel',
          ),
          IOSAuthMessages(
            cancelButton: 'Cancel',
          ),
        ],
      );
      return ok;
    } on PlatformException {
      // Covers PasscodeNotSet, NotEnrolled, LockedOut, etc. Treat every
      // platform error as "unlock failed" — the UI falls back to password.
      return false;
    }
  }

  /// Stops an in-progress authentication prompt. Call from screen dispose so
  /// a leftover prompt doesn't attach to the next screen.
  Future<void> stop() async {
    try {
      await _auth.stopAuthentication();
    } on PlatformException {
      // no-op
    }
  }
}
