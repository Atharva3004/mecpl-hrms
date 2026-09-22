// App Constants
class AppConstants {
  // App Info
  static const String appName = 'MECPL HRMS';
  static const String appVersion = '1.0.0';

  // Earliest date the app permits anywhere — calendars, date pickers, etc.
  // The HRMS rolled out on 2026-04-01; no historical data exists before
  // that. All `firstDate` parameters and the in-app attendance calendar
  // navigation use this floor.
  static final DateTime appStartDate = DateTime(2026, 4, 1);

  // Animation Durations
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 500);
  static const Duration animVerySlow = Duration(milliseconds: 800);

  // Padding & Spacing
  static const double paddingXS = 4.0;
  static const double paddingSM = 8.0;
  static const double paddingMD = 16.0;
  static const double paddingLG = 24.0;
  static const double paddingXL = 32.0;
  static const double paddingXXL = 48.0;

  // Border Radius
  static const double radiusXS = 4.0;
  static const double radiusSM = 8.0;
  static const double radiusMD = 12.0;
  static const double radiusLG = 16.0;
  static const double radiusXL = 20.0;
  static const double radiusXXL = 28.0;
  static const double radiusFull = 100.0;

  // Icon Sizes
  static const double iconSM = 18.0;
  static const double iconMD = 24.0;
  static const double iconLG = 32.0;
  static const double iconXL = 48.0;

  // Avatar Sizes
  static const double avatarSM = 32.0;
  static const double avatarMD = 48.0;
  static const double avatarLG = 64.0;
  static const double avatarXL = 96.0;

  // Card Sizes
  static const double cardElevation = 0.0;
  static const double cardBorderWidth = 1.0;

  // Bottom Nav
  static const double bottomNavHeight = 65.0;
  static const double bottomNavIconSize = 22.0;

  // Breakpoints
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 960.0;
  static const double desktopBreakpoint = 1280.0;
}
