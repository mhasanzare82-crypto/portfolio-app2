import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_page.dart';
import 'screens/theme_settings_page.dart';
import 'screens/color_settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  // =========================================================
  // بارگذاری سیستم رنگ جدید
  // =========================================================

  await AppColors.load();

  // =========================================================
  // سیستم رنگ قدیمی
  // برای حفظ تنظیمات قبلی برنامه نگه داشته شده است.
  // =========================================================

  final backgroundColor = _colorFromInt(
        prefs.getInt('theme_background_color'),
      ) ??
      const Color(0xffffffff);

  final textColor = _colorFromInt(
        prefs.getInt('theme_text_color'),
      ) ??
      const Color(0xff000000);

  final numberColor = _colorFromInt(
        prefs.getInt('theme_number_color'),
      ) ??
      const Color(0xfff1f0ec);

  final openPositionsColor = _colorFromInt(
        prefs.getInt('theme_open_positions_color'),
      ) ??
      const Color(0xff111827);

  final dashboardColor = _colorFromInt(
        prefs.getInt('theme_dashboard_color'),
      ) ??
      const Color(0xff172033);

  final reportsColor = _colorFromInt(
        prefs.getInt('theme_reports_color'),
      ) ??
      const Color(0xff1e293b);

  final customColor = _colorFromInt(
        prefs.getInt('theme_custom_color'),
      ) ??
      const Color(0xff202124);

  // =========================================================
  // اجرای برنامه
  // =========================================================

  runApp(
    LBankGoldApp(
      initialBackgroundColor: backgroundColor,
      initialTextColor: textColor,
      initialNumberColor: numberColor,
      initialOpenPositionsColor: openPositionsColor,
      initialDashboardColor: dashboardColor,
      initialReportsColor: reportsColor,
      initialCustomColor: customColor,
    ),
  );
}

Color? _colorFromInt(int? value) {
  if (value == null) {
    return null;
  }

  return Color(value);
}

// =============================================================
// برنامه اصلی
// =============================================================

class LBankGoldApp extends StatefulWidget {
  final Color initialBackgroundColor;
  final Color initialTextColor;
  final Color initialNumberColor;

  final Color initialOpenPositionsColor;
  final Color initialDashboardColor;
  final Color initialReportsColor;
  final Color initialCustomColor;

  const LBankGoldApp({
    super.key,
    required this.initialBackgroundColor,
    required this.initialTextColor,
    required this.initialNumberColor,
    required this.initialOpenPositionsColor,
    required this.initialDashboardColor,
    required this.initialReportsColor,
    required this.initialCustomColor,
  });

  @override
  State<LBankGoldApp> createState() => _LBankGoldAppState();
}

class _LBankGoldAppState extends State<LBankGoldApp> {
  late Color _backgroundColor;
  late Color _textColor;
  late Color _numberColor;

  late Color _openPositionsColor;
  late Color _dashboardColor;
  late Color _reportsColor;
  late Color _customColor;

  @override
  void initState() {
    super.initState();

    _backgroundColor = widget.initialBackgroundColor;
    _textColor = widget.initialTextColor;
    _numberColor = widget.initialNumberColor;

    _openPositionsColor = widget.initialOpenPositionsColor;
    _dashboardColor = widget.initialDashboardColor;
    _reportsColor = widget.initialReportsColor;
    _customColor = widget.initialCustomColor;
  }

  // ===========================================================
  // سیستم رنگ قدیمی
  // ===========================================================

  Future<void> _updateTheme({
    Color? backgroundColor,
    Color? textColor,
    Color? numberColor,
    Color? openPositionsColor,
    Color? dashboardColor,
    Color? reportsColor,
    Color? customColor,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) {
      return;
    }

    setState(() {
      if (backgroundColor != null) {
        _backgroundColor = backgroundColor;
      }

      if (textColor != null) {
        _textColor = textColor;
      }

      if (numberColor != null) {
        _numberColor = numberColor;
      }

      if (openPositionsColor != null) {
        _openPositionsColor = openPositionsColor;
      }

      if (dashboardColor != null) {
        _dashboardColor = dashboardColor;
      }

      if (reportsColor != null) {
        _reportsColor = reportsColor;
      }

      if (customColor != null) {
        _customColor = customColor;
      }
    });

    if (backgroundColor != null) {
      await prefs.setInt(
        'theme_background_color',
        backgroundColor.toARGB32(),
      );
    }

    if (textColor != null) {
      await prefs.setInt(
        'theme_text_color',
        textColor.toARGB32(),
      );
    }

    if (numberColor != null) {
      await prefs.setInt(
        'theme_number_color',
        numberColor.toARGB32(),
      );
    }

    if (openPositionsColor != null) {
      await prefs.setInt(
        'theme_open_positions_color',
        openPositionsColor.toARGB32(),
      );
    }

    if (dashboardColor != null) {
      await prefs.setInt(
        'theme_dashboard_color',
        dashboardColor.toARGB32(),
      );
    }

    if (reportsColor != null) {
      await prefs.setInt(
        'theme_reports_color',
        reportsColor.toARGB32(),
      );
    }

    if (customColor != null) {
      await prefs.setInt(
        'theme_custom_color',
        customColor.toARGB32(),
      );
    }
  }

  // ===========================================================
  // Theme اصلی برنامه
  // ===========================================================

  ThemeData _buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,

      // -------------------------------------------------------
      // پس‌زمینه کل برنامه
      // -------------------------------------------------------

      scaffoldBackgroundColor: AppColors.background,

      // -------------------------------------------------------
      // Color Scheme
      // -------------------------------------------------------

      colorScheme: ColorScheme.dark(
        surface: AppColors.background,
        primary: AppColors.button,
        onPrimary: AppColors.buttonText,
        secondary: AppColors.target,
        onSecondary: AppColors.buttonText,
        error: AppColors.error,
        onError: AppColors.buttonText,
        primaryContainer: AppColors.mainFrame,
        onPrimaryContainer: AppColors.text,
        secondaryContainer: AppColors.boxBackground,
        onSecondaryContainer: AppColors.text,
        surfaceContainerHighest: AppColors.boxBackground,
        onSurface: AppColors.text,
        onSurfaceVariant: AppColors.secondaryText,
      ),

      // -------------------------------------------------------
      // AppBar
      // -------------------------------------------------------

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.mainFrame,
        foregroundColor: AppColors.text,
        elevation: 0,
      ),

      // -------------------------------------------------------
      // متن‌ها
      // -------------------------------------------------------

      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: AppColors.text,
            displayColor: AppColors.text,
          ),

      // -------------------------------------------------------
      // آیکون‌ها
      // -------------------------------------------------------

      iconTheme: IconThemeData(
        color: AppColors.text,
      ),

      // -------------------------------------------------------
      // کارت‌ها
      // -------------------------------------------------------

      cardTheme: CardThemeData(
        color: AppColors.mainFrame,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: AppColors.border,
            width: 1,
          ),
        ),
      ),

      // -------------------------------------------------------
      // Divider
      // -------------------------------------------------------

      dividerTheme: DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
      ),

      dividerColor: AppColors.divider,

      // -------------------------------------------------------
      // فیلدهای ورودی
      // -------------------------------------------------------

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputBackground,
        labelStyle: TextStyle(
          color: AppColors.secondaryText,
        ),
        floatingLabelStyle: TextStyle(
          color: AppColors.inputFocusedBorder,
        ),
        hintStyle: TextStyle(
          color: AppColors.secondaryText,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.inputBorder,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.inputFocusedBorder,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.inputErrorBorder,
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.inputErrorBorder,
            width: 2,
          ),
        ),
      ),

      // -------------------------------------------------------
      // دکمه‌های معمولی
      // -------------------------------------------------------

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.button,
          foregroundColor: AppColors.buttonText,
        ),
      ),

      // -------------------------------------------------------
      // FilledButton
      // -------------------------------------------------------

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.button,
          foregroundColor: AppColors.buttonText,
        ),
      ),

      // -------------------------------------------------------
      // FloatingActionButton
      // -------------------------------------------------------

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.button,
        foregroundColor: AppColors.buttonText,
      ),

      // -------------------------------------------------------
      // NavigationBar
      // -------------------------------------------------------

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.navigationBackground,
        indicatorColor: AppColors.navigationSelected,
      ),

      // -------------------------------------------------------
      // Switch
      // -------------------------------------------------------

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.buttonText;
            }

            return AppColors.secondaryText;
          },
        ),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.button;
            }

            return AppColors.buttonDisabled;
          },
        ),
      ),

      // -------------------------------------------------------
      // Checkbox
      // -------------------------------------------------------

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.button;
            }

            return AppColors.inputBackground;
          },
        ),
        checkColor: WidgetStateProperty.all(
          AppColors.buttonText,
        ),
      ),

      // -------------------------------------------------------
      // Radio
      // -------------------------------------------------------

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.button;
            }

            return AppColors.secondaryText;
          },
        ),
      ),

      // -------------------------------------------------------
      // Progress Indicator
      // -------------------------------------------------------

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.button,
        linearTrackColor: AppColors.boxBackground,
      ),

      // -------------------------------------------------------
      // Slider
      // -------------------------------------------------------

      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.button,
        thumbColor: AppColors.button,
        inactiveTrackColor: AppColors.buttonDisabled,
        overlayColor: AppColors.button.withValues(
          alpha: 0.15,
        ),
      ),

      // -------------------------------------------------------
      // Dialog
      // -------------------------------------------------------

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.mainFrame,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: TextStyle(
          color: AppColors.secondaryText,
        ),
      ),

      // -------------------------------------------------------
      // Bottom Sheet
      // -------------------------------------------------------

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.mainFrame,
        surfaceTintColor: Colors.transparent,
      ),

      // -------------------------------------------------------
      // Popup Menu
      // -------------------------------------------------------

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.mainFrame,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(
          color: AppColors.text,
        ),
      ),

      // -------------------------------------------------------
      // SnackBar
      // -------------------------------------------------------

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.mainFrame,
        contentTextStyle: TextStyle(
          color: AppColors.text,
        ),
        actionTextColor: AppColors.button,
      ),
    );
  }

  // ===========================================================
  // ساخت برنامه
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'LBank GOLDUSDT',

      theme: _buildTheme(),

      // =======================================================
      // مسیرها
      // =======================================================

      routes: {
        // سیستم رنگ جدید
        '/color-settings': (context) {
          return const ColorSettingsPage();
        },

        // سیستم رنگ قبلی
        // برای حفظ قابلیت فعلی برنامه
        '/theme-settings': (context) {
          return ThemeSettingsPage(
            backgroundColor: _backgroundColor,
            textColor: _textColor,
            numberColor: _numberColor,
            openPositionsColor: _openPositionsColor,
            dashboardColor: _dashboardColor,
            reportsColor: _reportsColor,
            customColor: _customColor,
            onThemeChanged: _updateTheme,
          );
        },
      },

      home: const HomePage(),
    );
  }
}
