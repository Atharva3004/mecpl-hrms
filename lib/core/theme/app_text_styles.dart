// HRMS App Text Styles - Modern Typography
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  // Headings - Using Poppins for bold impact
  static TextStyle displayLarge = GoogleFonts.poppins(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
  ).copyWith(inherit: true);

  static TextStyle displayMedium = GoogleFonts.poppins(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
  ).copyWith(inherit: true);

  static TextStyle displaySmall = GoogleFonts.poppins(
    fontSize: 24,
    fontWeight: FontWeight.w600,
  ).copyWith(inherit: true);

  static TextStyle headlineLarge = GoogleFonts.poppins(
    fontSize: 22,
    fontWeight: FontWeight.w600,
  ).copyWith(inherit: true);

  static TextStyle headlineMedium = GoogleFonts.poppins(
    fontSize: 20,
    fontWeight: FontWeight.w600,
  ).copyWith(inherit: true);

  static TextStyle headlineSmall = GoogleFonts.poppins(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  ).copyWith(inherit: true);

  // Body Text - Using Inter for readability
  static TextStyle titleLarge = GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w500,
  ).copyWith(inherit: true);

  static TextStyle titleMedium = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
  ).copyWith(inherit: true);

  static TextStyle titleSmall = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  ).copyWith(inherit: true);

  static TextStyle bodyLarge = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.normal,
  ).copyWith(inherit: true);

  static TextStyle bodyMedium = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.normal,
  ).copyWith(inherit: true);

  static TextStyle bodySmall = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.normal,
  ).copyWith(inherit: true);

  static TextStyle labelLarge = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  ).copyWith(inherit: true);

  static TextStyle labelMedium = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
  ).copyWith(inherit: true);

  static TextStyle labelSmall = GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  ).copyWith(inherit: true);

  // Special Styles
  static TextStyle buttonText = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  ).copyWith(inherit: true);

  static TextStyle caption = GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.normal,
  ).copyWith(inherit: true);

  static TextStyle overline = GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.5,
  ).copyWith(inherit: true);

  // Number Styles (for stats)
  static TextStyle statLarge = GoogleFonts.poppins(
    fontSize: 36,
    fontWeight: FontWeight.bold,
  ).copyWith(inherit: true);

  static TextStyle statMedium = GoogleFonts.poppins(
    fontSize: 28,
    fontWeight: FontWeight.bold,
  ).copyWith(inherit: true);

  static TextStyle statSmall = GoogleFonts.poppins(
    fontSize: 20,
    fontWeight: FontWeight.w600,
  ).copyWith(inherit: true);
}
