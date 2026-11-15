import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'Overwatch';
  static const String appVersion = '4.7.0-Mobile';
  static const String publisher = 'Blackbox THC';

  // Default network configuration
  static const int defaultPort = 8765;
  static const String defaultHost = '192.168.30.74';
  static const String defaultAuthToken = 'LAN_GLASS_SECURE_2026';

  // Quality presets
  static const Map<String, int> qualityFps = {
    'Low': 15,
    'Medium': 30,
    'High': 60,
  };

  // Glassmorphic Theme Colors
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color cardBorderColor = Color(0x33475569);
  static const Color accentOrange = Color(0xFFFF9C00);
  static const Color accentBlue = Color(0xFF38BDF8);
  static const Color accentGreen = Color(0xFF22C55E);
  static const Color accentRed = Color(0xFFEF4444);
  static const Color textMuted = Color(0xFF94A3B8);
}
