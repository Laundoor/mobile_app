import 'package:flutter/material.dart';
import '../theme/admin_theme.dart';

Widget modalField(
  TextEditingController ctrl,
  String hint,
  IconData icon, {
  TextInputType type = TextInputType.text,
  bool obscure = false,
}) {
  return Container(
    decoration: BoxDecoration(
      color: AdminTheme.bg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AdminTheme.border),
    ),
    child: TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: type,
      style: const TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AdminTheme.textMuted),
        prefixIcon: Icon(icon, color: AdminTheme.textMuted, size: 20),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
            vertical: 14, horizontal: 16),
      ),
    ),
  );
}

Widget primaryButton(String label, bool loading) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF38B6FF), Color(0xFF1A90D9)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: AdminTheme.skyBlue.withOpacity(0.3),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Center(
      child: loading
          ? const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
          : Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
    ),
  );
}