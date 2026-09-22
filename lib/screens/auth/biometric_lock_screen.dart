// App-launch biometric unlock. Shown once before the MainShell every time
// the app opens after the user has opted in to biometric login. Falls back
// to the password login screen if the user taps "Use password" or if the
// biometric prompt fails.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/biometric_service.dart';

class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _promptInFlight = false;
  bool _lastAttemptFailed = false;
  List<BiometricType> _enrolled = const [];

  @override
  void initState() {
    super.initState();
    // Fire the prompt automatically on first frame so the user doesn't need
    // to tap the button — most banking apps behave this way.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _enrolled = await BiometricService.instance.availableBiometrics();
      if (!mounted) return;
      setState(() {});
      _runPrompt();
    });
  }

  @override
  void dispose() {
    BiometricService.instance.stop();
    super.dispose();
  }

  Future<void> _runPrompt() async {
    if (_promptInFlight) return;
    setState(() {
      _promptInFlight = true;
      _lastAttemptFailed = false;
    });
    final auth = context.read<AuthProvider>();
    final ok = await auth.unlockWithBiometric();
    if (!mounted) return;
    setState(() {
      _promptInFlight = false;
      _lastAttemptFailed = !ok;
    });
  }

  Future<void> _usePassword() async {
    await context.read<AuthProvider>().cancelBiometricAndShowLogin();
  }

  /// Picks the right icon + label based on which biometric the device has
  /// enrolled. Defaults to fingerprint — matches Android's dominant factor.
  ({IconData icon, String label}) _factorForUi() {
    if (_enrolled.contains(BiometricType.face)) {
      return (icon: Iconsax.scan, label: 'Face ID');
    }
    if (_enrolled.contains(BiometricType.iris)) {
      return (icon: Iconsax.eye, label: 'Iris Scan');
    }
    return (icon: Iconsax.finger_scan, label: 'Fingerprint');
  }

  @override
  Widget build(BuildContext context) {
    final factor = _factorForUi();
    final userName =
        context.watch<AuthProvider>().currentUser?.fullName ?? 'Welcome back';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Image.asset('assets/Mecpl_logo.png', height: 80),
              const SizedBox(height: 32),
              Text(
                userName,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Unlock with ${factor.label} to continue',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
              ),
              const Spacer(flex: 1),
              Center(
                child: GestureDetector(
                  onTap: _promptInFlight ? null : _runPrompt,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.25),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      factor.icon,
                      size: 44,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_lastAttemptFailed)
                Text(
                  'Authentication failed. Tap the icon to try again.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.red.shade700,
                  ),
                )
              else
                Text(
                  _promptInFlight
                      ? 'Waiting for ${factor.label}…'
                      : 'Tap to try again',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
              const Spacer(flex: 2),

              // TextButton(
              //   onPressed: _usePassword,
              //   child: Text(
              //     'Use password instead',
              //     style: GoogleFonts.poppins(
              //       fontSize: 14,
              //       fontWeight: FontWeight.w600,
              //       color: AppColors.primary,
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}
