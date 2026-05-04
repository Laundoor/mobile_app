import 'package:flutter/material.dart';

class AdminTheme {
  static const Color bg           = Color(0xFFF4F8FF);
  static const Color white        = Color(0xFFFFFFFF);
  static const Color skyBlue      = Color(0xFF38B6FF);
  static const Color skyLight     = Color(0xFFE8F5FF);
  static const Color skyDark      = Color(0xFF1A90D9);
  static const Color success      = Color(0xFF22C55E);
  static const Color successLight = Color(0xFFECFDF5);
  static const Color warning      = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFFFBEB);
  static const Color error        = Color(0xFFEF4444);
  static const Color errorLight   = Color(0xFFFEF2F2);
  static const Color textPrimary  = Color(0xFF0F172A);
  static const Color textMuted    = Color(0xFF64748B);
  static const Color border       = Color(0xFFDDE8F5);
  static const Color pending      = Color(0xFFF59E0B);
  static const Color inProgress   = Color(0xFF38B6FF);
  static const Color completed    = Color(0xFF22C55E);
  static const Color cancelled    = Color(0xFFEF4444);

  static Color statusColor(String status) {
    switch (status) {
      case 'In Progress': return inProgress;
      case 'Completed':   return completed;
      case 'Cancelled':   return cancelled;
      default:            return pending;
    }
  }

  static Color statusBg(String status) {
    switch (status) {
      case 'In Progress': return skyLight;
      case 'Completed':   return successLight;
      case 'Cancelled':   return errorLight;
      default:            return warningLight;
    }
  }
}