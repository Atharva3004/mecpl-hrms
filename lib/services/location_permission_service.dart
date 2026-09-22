// Location Permission Dialog Service - Google Play Compliant Prominent Disclosure
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import '../core/theme/app_colors.dart';
import '../screens/settings/privacy_policy_screen.dart';

class LocationPermissionService {
  /// Google Play Compliant - Prominent Disclosure and Consent
  /// Shows a full-screen prominent disclosure BEFORE requesting system permission.
  /// Must include: "location", "background"/"when the app is closed or not in use",
  /// specific features, and a link to privacy policy.
  static Future<bool> showPermissionDialog(BuildContext context) async {
    // Step 1: Show Prominent Disclosure dialog FIRST (before any system dialogs)
    print('📍 Step 1: Showing Google Play compliant prominent disclosure...');

    final userConsent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Location Icon
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.15),
                        AppColors.primary.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    size: 44,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 20),

                // Title - Must be prominent and clear
                Text(
                  'Background Location Access',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // ═══════════════════════════════════════════════
                // GOOGLE PLAY REQUIRED: Prominent Disclosure Text
                // Must follow Google's recommended template:
                // "This app collects location data to enable [feature]
                //  even when the app is closed or not in use."
                // ═══════════════════════════════════════════════
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Text(
                    'This app collects location data to enable attendance tracking and geofencing verification even when the app is closed or not in use.',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue[900],
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),

                // Feature List - Specific features using background location
                _buildFeatureItem(
                  Icons.fingerprint_rounded,
                  'Attendance Verification',
                  'Verifies your work location when you punch in and punch out.',
                ),
                const SizedBox(height: 10),
                _buildFeatureItem(
                  Icons.radar_rounded,
                  'Geofencing',
                  'Checks if you are within the designated office area for attendance.',
                ),
                const SizedBox(height: 10),
                _buildFeatureItem(
                  Icons.route_rounded,
                  'Location Tracking',
                  'Tracks your location during work hours to record your movement history.',
                ),
                const SizedBox(height: 16),

                // Background usage warning - REQUIRED by Google
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange[300]!),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_rounded,
                        size: 20,
                        color: Colors.orange[800],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Location data is collected in the background even when the app is closed or not in use. This is required for accurate attendance and geofence monitoring.',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.orange[900],
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Data protection notice
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green[300]!),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.shield_rounded,
                        size: 20,
                        color: Colors.green[800],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your location data is not shared with third parties and is used only for HR management purposes.',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.green[900],
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Privacy Policy Link - REQUIRED by Google
                Builder(
                  builder: (context) => RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[600],
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(
                          text: 'By tapping "I Agree", you consent to the collection and use of your location data as described above and in our ',
                        ),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PrivacyPolicyScreen(),
                                ),
                              );
                            },
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Action Buttons - "I Agree" / "No Thanks"
                Row(
                  children: [
                    // No Thanks Button
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Colors.grey[400]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'No Thanks',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // I Agree Button
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'I Agree',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // If user denied consent, return false
    if (userConsent != true) {
      print('❌ User denied prominent disclosure consent');
      return false;
    }

    // Small delay to ensure dialog is fully closed
    await Future.delayed(const Duration(milliseconds: 300));

    // Step 2: User clicked "I Agree" - NOW request system permission
    print('📍 Step 2: Requesting system location permission...');

    try {
      // Request system permission
      print('📱 Showing system permission popup...');
      LocationPermission permission = await Geolocator.requestPermission();

      // Check if permission was granted
      if (permission == LocationPermission.deniedForever) {
        print('❌ Permission permanently denied');
        return false;
      }

      if (permission == LocationPermission.denied) {
        print('❌ Permission denied by user in system popup');
        return false;
      }

      // Foreground permission granted (whileInUse or always). Punching only
      // needs this much, so from here on the result is always `true` — the
      // background escalation below is best-effort and must never block a
      // punch.
      print('✅ System location permission granted');

      // Android 10+ (API 29+) grants foreground-only from the prompt above.
      // ACCESS_BACKGROUND_LOCATION is a *separate* grant, and without it the
      // 30-minute Workmanager ping can't get a fix once the app is
      // backgrounded — it fails silently and no ping is ever sent.
      if (permission != LocationPermission.always && context.mounted) {
        await _requestBackgroundLocation(context);
      }

      return true;
    } catch (e) {
      print('❌ Error requesting location permission: $e');
      return false;
    }
  }

  /// Second-stage escalation to "Allow all the time"
  /// (`ACCESS_BACKGROUND_LOCATION`), required for the 30-minute attendance
  /// pings to keep firing once the app is backgrounded or killed.
  ///
  /// Best-effort by design: attendance punching only needs foreground
  /// location, so a refusal here is never fatal and the caller ignores the
  /// result. On Android 11+ the system no longer grants this from an in-app
  /// prompt at all — the user has to pick "Allow all the time" in Settings,
  /// so we explain why and hand them there rather than silently failing.
  static Future<void> _requestBackgroundLocation(BuildContext context) async {
    print('📍 Step 3: Requesting background ("Allow all the time") location...');

    // Android 10 can still grant this from a system prompt; 11+ returns the
    // existing whileInUse without showing anything. Try the cheap path first.
    try {
      final escalated = await Geolocator.requestPermission();
      if (escalated == LocationPermission.always) {
        print('✅ Background location granted');
        return;
      }
    } catch (e) {
      print('⚠️ Background location request failed: $e');
    }

    if (!context.mounted) return;

    final goToSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Enable background location',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'To record your attendance trail while the app is closed, Android '
          'needs location set to "Allow all the time".\n\n'
          'Open Settings → Permissions → Location, then choose '
          '"Allow all the time".\n\n'
          'You can still punch in and out without this, but your location '
          'tracking will stop when the app is in the background.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Not now', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Open Settings',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );

    if (goToSettings == true) {
      try {
        await Geolocator.openAppSettings();
      } catch (e) {
        print('⚠️ Could not open app settings: $e');
      }
    }
  }

  /// Helper widget to build feature list items
  static Widget _buildFeatureItem(
    IconData icon,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
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
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
