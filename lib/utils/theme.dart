import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors
  static const Color primaryGold =
      Color(0xFFFFA000); // Updated to match gold accents request
  static const Color secondaryGold = Color(0xFFFFB300);
  static const Color backgroundCharcoal = Color(0xFF121212);
  static const Color surfaceGrey = Color(0xFF1E1E1E);

  // Admin Professional Palette (Modern Enterprise)
  static const Color adminBg = Color(0xFF0B0F1A); // Deep Navy Black
  static const Color adminSurface = Color(0xFF161B29); // Slate Navy
  static const Color adminPrimary = Color(0xFFEAB308); // Modern Gold
  static const Color adminSecondary = Color(0xFF38BDF8); // Sky Blue (for info)
  static const Color adminMuted = Color(0xFF64748B);

  static ThemeData adminTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: adminPrimary,
    scaffoldBackgroundColor: adminBg,
    canvasColor: adminSurface,
    fontFamily: GoogleFonts.inter().fontFamily,
    colorScheme: const ColorScheme.dark(
      primary: adminPrimary,
      secondary: adminSecondary,
      surface: adminSurface,
      onPrimary: Colors.black,
      onSurface: Colors.white,
      error: Color(0xFFF87171),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      backgroundColor: adminBg,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: adminSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1E2533),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: adminPrimary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: adminPrimary,
        foregroundColor: Colors.black,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    ),
  );

  static ThemeData lightMidnightGoldTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: primaryGold,
    scaffoldBackgroundColor: const Color(0xFFF5F5F5),
    fontFamily: GoogleFonts.poppins().fontFamily,
    colorScheme: const ColorScheme.light(
      primary: primaryGold,
      secondary: secondaryGold,
      surface: Colors.white,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: Colors.black,
    ),
    textTheme:
        GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme).copyWith(
      bodyLarge: const TextStyle(color: Colors.black),
      bodyMedium: const TextStyle(color: Colors.black87),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Colors.white,
      foregroundColor: primaryGold,
      titleTextStyle: GoogleFonts.poppins(
        color: primaryGold,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: const IconThemeData(color: primaryGold),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryGold,
        foregroundColor: Colors.black,
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
  );

  static ThemeData midnightGoldTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: primaryGold,
    scaffoldBackgroundColor: Colors.black,
    fontFamily: GoogleFonts.poppins().fontFamily,
    colorScheme: const ColorScheme.dark(
      primary: primaryGold,
      secondary: secondaryGold,
      surface: Color(0xFF121212),
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: Colors.white,
    ),
    textTheme:
        GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme).copyWith(
      bodyLarge: const TextStyle(color: Colors.white),
      bodyMedium: const TextStyle(color: Colors.white70),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Colors.black,
      foregroundColor: primaryGold,
      titleTextStyle: GoogleFonts.poppins(
        color: primaryGold,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: const IconThemeData(color: primaryGold),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.black,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryGold,
        foregroundColor: Colors.black,
        minimumSize: const Size(double.infinity, 55),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: const BorderSide(color: Colors.black, width: 1),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryGold,
        side: const BorderSide(color: primaryGold, width: 1.5),
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: primaryGold.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: primaryGold.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: primaryGold, width: 2),
      ),
      labelStyle: const TextStyle(color: primaryGold),
      hintStyle: const TextStyle(color: Colors.white38),
      prefixIconColor: primaryGold,
    ),
  );

  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: Colors.blue.shade900,
    scaffoldBackgroundColor: Colors.white,
    fontFamily: GoogleFonts.poppins().fontFamily,
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Colors.blue.shade900,
      foregroundColor: Colors.white,
      titleTextStyle: GoogleFonts.poppins(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: Colors.blue.shade400,
    scaffoldBackgroundColor: Colors.grey.shade900,
    fontFamily: GoogleFonts.poppins().fontFamily,
  );
}
