import 'package:flutter/material.dart';

import 'color_settings_page.dart';

class ThemeSettingsPage extends StatelessWidget {
  // این پارامترها برای حفظ سازگاری با کدهای قبلی برنامه نگه داشته شده‌اند.
  final Color backgroundColor;
  final Color textColor;
  final Color numberColor;

  final Color openPositionsColor;
  final Color dashboardColor;
  final Color reportsColor;
  final Color customColor;

  final Future<void> Function({
    Color? backgroundColor,
    Color? textColor,
    Color? numberColor,
    Color? openPositionsColor,
    Color? dashboardColor,
    Color? reportsColor,
    Color? customColor,
  }) onThemeChanged;

  const ThemeSettingsPage({
    super.key,
    required this.backgroundColor,
    required this.textColor,
    required this.numberColor,
    required this.openPositionsColor,
    required this.dashboardColor,
    required this.reportsColor,
    required this.customColor,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return const ColorSettingsPage();
  }
}
