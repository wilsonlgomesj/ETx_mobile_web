import 'package:flutter/material.dart';

class AppColors {
  static const teal     = Color(0xFF1A8A8A);
  static const tealDk   = Color(0xFF136B6B);
  static const tealLt   = Color(0xFFE8F5F5);
  static const tealMid  = Color(0xFF2AA8A8);
  static const bg       = Color(0xFFF5F7F7);
  static const surf     = Color(0xFFFFFFFF);
  static const raised   = Color(0xFFEDF4F4);
  static const line     = Color(0xFFDDEAEA);
  static const line2    = Color(0xFFEEF4F4);
  static const textMain = Color(0xFF172929);
  static const sub      = Color(0xFF5A8585);
  static const sub2     = Color(0xFF9EBDBD);
  static const warn     = Color(0xFFF07A2A);
  static const danger   = Color(0xFFDC2626);
  static const green    = Color(0xFF16A34A);
  static const accDim   = Color(0xFFE0F2F2);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.teal,
      surface: AppColors.surf,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'SF Pro Display',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surf,
      foregroundColor: AppColors.textMain,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textMain),
      headlineMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textMain),
      titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textMain),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMain),
      titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain),
      bodyLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textMain),
      bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textMain),
      bodySmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.sub),
      labelSmall: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.sub, letterSpacing: 1.2),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surf,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.line),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.line,
      thickness: 1,
      space: 0,
    ),
  );
}
