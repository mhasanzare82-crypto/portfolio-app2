import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppColors {
  // =========================
  // رنگ‌های عمومی
  // =========================

  static Color background = const Color(0xFF0D1117);
  static Color mainFrame = const Color(0xFF0B1F3A);
  static Color cardBackground = const Color(0xFF111827);
  static Color boxBackground = const Color(0xFF172033);

  static Color text = Colors.white;
  static Color secondaryText = const Color(0xFFB0B8C4);
  static Color disabledText = const Color(0xFF6B7280);

  static Color border = const Color(0xFF374151);
  static Color divider = const Color(0xFF374151);

  // =========================
  // رنگ‌های معاملات
  // =========================

  static Color profit = const Color(0xFF00C853);
  static Color loss = const Color(0xFFF44336);
  static Color neutral = const Color(0xFFB0B8C4);

  static Color long = const Color(0xFF00C853);
  static Color short = const Color(0xFFF44336);

  static Color stop = const Color(0xFFF44336);
  static Color entry = const Color(0xFF2196F3);
  static Color target = const Color(0xFFFF9800);

  static Color livePrice = const Color(0xFFFFC107);
  static Color drawdown = const Color(0xFFF44336);

  // =========================
  // رنگ بخش‌های اصلی
  // =========================

  static Color openPositions = const Color(0xFF111827);
  static Color dashboard = const Color(0xFF172033);
  static Color reports = const Color(0xFF1E293B);
  static Color custom = const Color(0xFF202124);

  // =========================
  // رنگ نوار پایین
  // =========================

  static Color navigationBackground = const Color(0xFF111827);
  static Color navigationSelected = const Color(0xFF2196F3);
  static Color navigationUnselected = const Color(0xFF9CA3AF);

  // =========================
  // دکمه‌ها
  // =========================

  static Color button = const Color(0xFF2196F3);
  static Color buttonText = Colors.white;
  static Color buttonDisabled = const Color(0xFF374151);

  // =========================
  // فیلدهای ورودی
  // =========================

  static Color inputBackground = const Color(0xFF172033);
  static Color inputBorder = const Color(0xFF374151);
  static Color inputFocusedBorder = const Color(0xFF2196F3);
  static Color inputErrorBorder = const Color(0xFFF44336);

  // =========================
  // نمودار
  // =========================

  static Color chartGrid = const Color(0xFFFF9406);
  static Color chartLine = const Color(0xFFFF00AB);
  static Color chartPoint = const Color(0xFFFF07EA);
  static Color chartText = const Color(0xFFD9067DED);

  // =========================
  // هشدارها و وضعیت‌ها
  // =========================

  static Color success = const Color(0xFF00C853);
  static Color warning = const Color(0xFFFFC107);
  static Color error = const Color(0xFFF44336);

  static Color alertActive = const Color(0xFF2196F3);
  static Color alertInactive = const Color(0xFF808080);

  // =========================
  // سایر موارد
  // =========================

  static Color required = const Color(0xFFF44336);
  static Color emptyIcon = const Color(0xFF757575);
  static Color emptyDescription = const Color(0xFF9E9E9E);

  static Color imageDeleteBackground = const Color(0x99000000);
  static Color imageDeleteIcon = Colors.white;

  static Color dragHelper = const Color(0x8AFFFFFF);
  static Color parameterDivider = const Color(0x1FFFFFFF);

  static Color assetIcon = const Color(0xFFFFC107);
  static Color assetIconBackground = const Color(0x1FFFFC107);

  static Color chevron = const Color(0x8AFFFFFF);

  // ============================================================
  // کلیدهای رنگ
  // ============================================================

  static final List<String> colorKeys = [
    'background',
    'mainFrame',
    'cardBackground',
    'boxBackground',
    'text',
    'secondaryText',
    'disabledText',
    'border',
    'divider',
    'profit',
    'loss',
    'neutral',
    'long',
    'short',
    'stop',
    'entry',
    'target',
    'livePrice',
    'drawdown',
    'openPositions',
    'dashboard',
    'reports',
    'custom',
    'navigationBackground',
    'navigationSelected',
    'navigationUnselected',
    'button',
    'buttonText',
    'buttonDisabled',
    'inputBackground',
    'inputBorder',
    'inputFocusedBorder',
    'inputErrorBorder',
    'chartGrid',
    'chartLine',
    'chartPoint',
    'chartText',
    'success',
    'warning',
    'error',
    'alertActive',
    'alertInactive',
    'required',
    'emptyIcon',
    'emptyDescription',
    'imageDeleteBackground',
    'imageDeleteIcon',
    'dragHelper',
    'parameterDivider',
    'assetIcon',
    'assetIconBackground',
    'chevron',
  ];

  // ============================================================
  // دریافت رنگ بر اساس کلید
  // ============================================================

  static Color getColor(String key) {
    switch (key) {
      case 'background':
        return background;
      case 'mainFrame':
        return mainFrame;
      case 'cardBackground':
        return cardBackground;
      case 'boxBackground':
        return boxBackground;
      case 'text':
        return text;
      case 'secondaryText':
        return secondaryText;
      case 'disabledText':
        return disabledText;
      case 'border':
        return border;
      case 'divider':
        return divider;
      case 'profit':
        return profit;
      case 'loss':
        return loss;
      case 'neutral':
        return neutral;
      case 'long':
        return long;
      case 'short':
        return short;
      case 'stop':
        return stop;
      case 'entry':
        return entry;
      case 'target':
        return target;
      case 'livePrice':
        return livePrice;
      case 'drawdown':
        return drawdown;
      case 'openPositions':
        return openPositions;
      case 'dashboard':
        return dashboard;
      case 'reports':
        return reports;
      case 'custom':
        return custom;
      case 'navigationBackground':
        return navigationBackground;
      case 'navigationSelected':
        return navigationSelected;
      case 'navigationUnselected':
        return navigationUnselected;
      case 'button':
        return button;
      case 'buttonText':
        return buttonText;
      case 'buttonDisabled':
        return buttonDisabled;
      case 'inputBackground':
        return inputBackground;
      case 'inputBorder':
        return inputBorder;
      case 'inputFocusedBorder':
        return inputFocusedBorder;
      case 'inputErrorBorder':
        return inputErrorBorder;
      case 'chartGrid':
        return chartGrid;
      case 'chartLine':
        return chartLine;
      case 'chartPoint':
        return chartPoint;
      case 'chartText':
        return chartText;
      case 'success':
        return success;
      case 'warning':
        return warning;
      case 'error':
        return error;
      case 'alertActive':
        return alertActive;
      case 'alertInactive':
        return alertInactive;
      case 'required':
        return required;
      case 'emptyIcon':
        return emptyIcon;
      case 'emptyDescription':
        return emptyDescription;
      case 'imageDeleteBackground':
        return imageDeleteBackground;
      case 'imageDeleteIcon':
        return imageDeleteIcon;
      case 'dragHelper':
        return dragHelper;
      case 'parameterDivider':
        return parameterDivider;
      case 'assetIcon':
        return assetIcon;
      case 'assetIconBackground':
        return assetIconBackground;
      case 'chevron':
        return chevron;
    }

    return Colors.white;
  }

  // ============================================================
  // تغییر رنگ بر اساس کلید
  // ============================================================

  static void setColor(String key, Color color) {
    switch (key) {
      case 'background':
        background = color;
        break;
      case 'mainFrame':
        mainFrame = color;
        break;
      case 'cardBackground':
        cardBackground = color;
        break;
      case 'boxBackground':
        boxBackground = color;
        break;
      case 'text':
        text = color;
        break;
      case 'secondaryText':
        secondaryText = color;
        break;
      case 'disabledText':
        disabledText = color;
        break;
      case 'border':
        border = color;
        break;
      case 'divider':
        divider = color;
        break;
      case 'profit':
        profit = color;
        break;
      case 'loss':
        loss = color;
        break;
      case 'neutral':
        neutral = color;
        break;
      case 'long':
        long = color;
        break;
      case 'short':
        short = color;
        break;
      case 'stop':
        stop = color;
        break;
      case 'entry':
        entry = color;
        break;
      case 'target':
        target = color;
        break;
      case 'livePrice':
        livePrice = color;
        break;
      case 'drawdown':
        drawdown = color;
        break;
      case 'openPositions':
        openPositions = color;
        break;
      case 'dashboard':
        dashboard = color;
        break;
      case 'reports':
        reports = color;
        break;
      case 'custom':
        custom = color;
        break;
      case 'navigationBackground':
        navigationBackground = color;
        break;
      case 'navigationSelected':
        navigationSelected = color;
        break;
      case 'navigationUnselected':
        navigationUnselected = color;
        break;
      case 'button':
        button = color;
        break;
      case 'buttonText':
        buttonText = color;
        break;
      case 'buttonDisabled':
        buttonDisabled = color;
        break;
      case 'inputBackground':
        inputBackground = color;
        break;
      case 'inputBorder':
        inputBorder = color;
        break;
      case 'inputFocusedBorder':
        inputFocusedBorder = color;
        break;
      case 'inputErrorBorder':
        inputErrorBorder = color;
        break;
      case 'chartGrid':
        chartGrid = color;
        break;
      case 'chartLine':
        chartLine = color;
        break;
      case 'chartPoint':
        chartPoint = color;
        break;
      case 'chartText':
        chartText = color;
        break;
      case 'success':
        success = color;
        break;
      case 'warning':
        warning = color;
        break;
      case 'error':
        error = color;
        break;
      case 'alertActive':
        alertActive = color;
        break;
      case 'alertInactive':
        alertInactive = color;
        break;
      case 'required':
        required = color;
        break;
      case 'emptyIcon':
        emptyIcon = color;
        break;
      case 'emptyDescription':
        emptyDescription = color;
        break;
      case 'imageDeleteBackground':
        imageDeleteBackground = color;
        break;
      case 'imageDeleteIcon':
        imageDeleteIcon = color;
        break;
      case 'dragHelper':
        dragHelper = color;
        break;
      case 'parameterDivider':
        parameterDivider = color;
        break;
      case 'assetIcon':
        assetIcon = color;
        break;
      case 'assetIconBackground':
        assetIconBackground = color;
        break;
      case 'chevron':
        chevron = color;
        break;
    }
  }

  // ============================================================
  // ذخیره یک رنگ
  // ============================================================

  static Future<void> save(
    String key,
    Color color,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(
      'app_color_$key',
      color.toARGB32(),
    );
  }

  // ============================================================
  // بارگذاری رنگ‌های فعلی
  // ============================================================

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    for (final key in colorKeys) {
      final value = prefs.getInt('app_color_$key');

      if (value != null) {
        setColor(
          key,
          Color(value),
        );
      }
    }
  }

  // ============================================================
  // گرفتن تمام رنگ‌های فعلی
  // ============================================================

  static Map<String, int> getCurrentColors() {
    final Map<String, int> result = {};

    for (final key in colorKeys) {
      result[key] = getColor(key).toARGB32();
    }

    return result;
  }

  // ============================================================
  // اعمال یک مجموعه رنگ
  // ============================================================

  static void applyColors(
    Map<String, dynamic> colors,
  ) {
    colors.forEach(
      (key, value) {
        if (!colorKeys.contains(key)) {
          return;
        }

        if (value is int) {
          setColor(
            key,
            Color(value),
          );
        } else if (value is num) {
          setColor(
            key,
            Color(value.toInt()),
          );
        }
      },
    );
  }

  // ============================================================
  // ذخیره مجموعه رنگ
  // ============================================================

  static Future<void> saveColorPreset(
    String name,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final presets = await getColorPresets();

    final colors = getCurrentColors();

    presets[name] = colors;

    await prefs.setString(
      'color_presets',
      jsonEncode(presets),
    );
  }

  // ============================================================
  // دریافت مجموعه‌های ذخیره‌شده
  // ============================================================

  static Future<Map<String, Map<String, dynamic>>> getColorPresets() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(
      'color_presets',
    );

    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        return {};
      }

      final result = <String, Map<String, dynamic>>{};

      decoded.forEach(
        (key, value) {
          if (key is String && value is Map) {
            result[key] = Map<String, dynamic>.from(value);
          }
        },
      );

      return result;
    } catch (_) {
      return {};
    }
  }

  // ============================================================
  // حذف مجموعه رنگ
  // ============================================================

  static Future<void> deleteColorPreset(
    String name,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final presets = await getColorPresets();

    presets.remove(name);

    await prefs.setString(
      'color_presets',
      jsonEncode(presets),
    );
  }

  // ============================================================
  // اعمال و ذخیره یک مجموعه رنگ
  // ============================================================

  static Future<void> applyColorPreset(
    String name,
  ) async {
    final presets = await getColorPresets();

    final colors = presets[name];

    if (colors == null) {
      return;
    }

    applyColors(colors);

    final prefs = await SharedPreferences.getInstance();

    for (final key in colorKeys) {
      final color = getColor(key);

      await prefs.setInt(
        'app_color_$key',
        color.toARGB32(),
      );
    }
  }
}

// ================================================================
// صفحه تنظیمات رنگ
// ================================================================

class ColorSettingsPage extends StatefulWidget {
  const ColorSettingsPage({
    super.key,
  });

  @override
  State<ColorSettingsPage> createState() => _ColorSettingsPageState();
}

class _ColorSettingsPageState extends State<ColorSettingsPage> {
  final List<_ColorItem> _items = [
    // عمومی
    _ColorItem('پس‌زمینه کل برنامه', 'background'),
    _ColorItem(
      'قاب اصلی برنامه - سورمه‌ای',
      'mainFrame',
    ),
    _ColorItem(
      'پس‌زمینه کارت‌ها',
      'cardBackground',
    ),
    _ColorItem(
      'پس‌زمینه باکس‌ها',
      'boxBackground',
    ),
    _ColorItem('رنگ متن اصلی', 'text'),
    _ColorItem(
      'رنگ متن فرعی',
      'secondaryText',
    ),
    _ColorItem(
      'رنگ متن غیرفعال',
      'disabledText',
    ),
    _ColorItem('رنگ کادرها', 'border'),
    _ColorItem(
      'رنگ خطوط جداکننده',
      'divider',
    ),

    // معاملات
    _ColorItem('رنگ سود', 'profit'),
    _ColorItem('رنگ ضرر', 'loss'),
    _ColorItem('رنگ خنثی', 'neutral'),
    _ColorItem('رنگ LONG', 'long'),
    _ColorItem('رنگ SHORT', 'short'),
    _ColorItem('رنگ Stop', 'stop'),
    _ColorItem('رنگ Entry', 'entry'),
    _ColorItem('رنگ Target', 'target'),
    _ColorItem(
      'رنگ قیمت لحظه‌ای',
      'livePrice',
    ),
    _ColorItem(
      'رنگ Drawdown',
      'drawdown',
    ),

    // بخش‌های اصلی
    _ColorItem(
      'رنگ معاملات باز',
      'openPositions',
    ),
    _ColorItem(
      'رنگ داشبورد',
      'dashboard',
    ),
    _ColorItem(
      'رنگ گزارش‌ها',
      'reports',
    ),
    _ColorItem(
      'رنگ موارد سفارشی',
      'custom',
    ),

    // نوار پایین
    _ColorItem(
      'پس‌زمینه نوار پایین',
      'navigationBackground',
    ),
    _ColorItem(
      'آیتم انتخاب‌شده نوار پایین',
      'navigationSelected',
    ),
    _ColorItem(
      'آیتم انتخاب‌نشده نوار پایین',
      'navigationUnselected',
    ),

    // دکمه‌ها
    _ColorItem('رنگ دکمه‌ها', 'button'),
    _ColorItem(
      'رنگ متن دکمه‌ها',
      'buttonText',
    ),
    _ColorItem(
      'رنگ دکمه غیرفعال',
      'buttonDisabled',
    ),

    // فیلدها
    _ColorItem(
      'پس‌زمینه فیلدها',
      'inputBackground',
    ),
    _ColorItem(
      'کادر فیلدها',
      'inputBorder',
    ),
    _ColorItem(
      'کادر فیلد انتخاب‌شده',
      'inputFocusedBorder',
    ),
    _ColorItem(
      'کادر خطای فیلد',
      'inputErrorBorder',
    ),

    // نمودار
    _ColorItem(
      'شبکه نمودار',
      'chartGrid',
    ),
    _ColorItem(
      'خط نمودار',
      'chartLine',
    ),
    _ColorItem(
      'نقاط نمودار',
      'chartPoint',
    ),
    _ColorItem(
      'نوشته‌های نمودار',
      'chartText',
    ),

    // وضعیت
    _ColorItem('موفقیت', 'success'),
    _ColorItem('هشدار', 'warning'),
    _ColorItem('خطا', 'error'),
    _ColorItem(
      'هشدار فعال',
      'alertActive',
    ),
    _ColorItem(
      'هشدار غیرفعال',
      'alertInactive',
    ),

    // سایر
    _ColorItem(
      'علامت فیلد اجباری',
      'required',
    ),
    _ColorItem(
      'آیکون صفحه خالی',
      'emptyIcon',
    ),
    _ColorItem(
      'توضیح صفحه خالی',
      'emptyDescription',
    ),
    _ColorItem(
      'پس‌زمینه حذف تصویر',
      'imageDeleteBackground',
    ),
    _ColorItem(
      'آیکون حذف تصویر',
      'imageDeleteIcon',
    ),
    _ColorItem(
      'متن راهنمای جابه‌جایی',
      'dragHelper',
    ),
    _ColorItem(
      'جداکننده پارامترها',
      'parameterDivider',
    ),
    _ColorItem(
      'آیکون دارایی',
      'assetIcon',
    ),
    _ColorItem(
      'پس‌زمینه آیکون دارایی',
      'assetIconBackground',
    ),
    _ColorItem(
      'آیکون فلش',
      'chevron',
    ),
  ];

  List<String> _presetNames = [];
  bool _loadingPresets = true;

  @override
  void initState() {
    super.initState();

    _loadPresets();
  }

  // ============================================================
  // بارگذاری تنظیمات ذخیره‌شده
  // ============================================================

  Future<void> _loadPresets() async {
    final presets = await AppColors.getColorPresets();

    if (!mounted) {
      return;
    }

    setState(() {
      _presetNames = presets.keys.toList();
      _loadingPresets = false;
    });
  }

  // ============================================================
  // انتخاب رنگ
  // ============================================================

  Future<void> _pickColor(
    _ColorItem item,
  ) async {
    final currentColor = item.getColor();

    final result = await showDialog<Color>(
      context: context,
      builder: (context) {
        return _ColorPickerDialog(
          title: item.title,
          initialColor: currentColor,
        );
      },
    );

    if (result == null) {
      return;
    }

    item.setColor(result);

    await AppColors.save(
      item.key,
      result,
    );

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // ============================================================
  // ذخیره تنظیمات فعلی
  // ============================================================

  Future<void> _saveCurrentPreset() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'ذخیره تنظیمات رنگ',
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'نام تنظیم رنگ',
              hintText: 'مثلاً تم طلایی',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('لغو'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();

                if (value.isEmpty) {
                  return;
                }

                Navigator.pop(
                  context,
                  value,
                );
              },
              child: const Text('ذخیره'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (name == null || name.trim().isEmpty) {
      return;
    }

    final cleanName = name.trim();

    final existing = await AppColors.getColorPresets();

    if (existing.containsKey(cleanName)) {
      final replace = await _showReplaceDialog(
        cleanName,
      );

      if (!replace) {
        return;
      }
    }

    await AppColors.saveColorPreset(
      cleanName,
    );

    await _loadPresets();

    if (!mounted) {
      return;
    }

    _showMessage(
      'تنظیم رنگ «$cleanName» ذخیره شد.',
    );
  }

  // ============================================================
  // تأیید جایگزینی
  // ============================================================

  Future<bool> _showReplaceDialog(
    String name,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'تنظیم موجود است',
          ),
          content: Text(
            'تنظیم رنگ «$name» قبلاً ذخیره شده است. آیا می‌خواهید آن را با رنگ‌های فعلی جایگزین کنید؟',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text('لغو'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text('جایگزین کن'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  // ============================================================
  // اعمال تنظیم
  // ============================================================

  Future<void> _applyPreset(
    String name,
  ) async {
    await AppColors.applyColorPreset(
      name,
    );

    if (!mounted) {
      return;
    }

    setState(() {});

    _showMessage(
      'تنظیم رنگ «$name» اعمال شد.',
    );
  }

  // ============================================================
  // حذف تنظیم
  // ============================================================

  Future<void> _deletePreset(
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'حذف تنظیم رنگ',
          ),
          content: Text(
            'آیا می‌خواهید تنظیم «$name» حذف شود؟',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text('لغو'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await AppColors.deleteColorPreset(
      name,
    );

    await _loadPresets();

    if (!mounted) {
      return;
    }

    _showMessage(
      'تنظیم «$name» حذف شد.',
    );
  }

  // ============================================================
  // پیام
  // ============================================================

  void _showMessage(
    String message,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تنظیمات رنگ',
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPresetActions(),
          const SizedBox(height: 20),
          _buildSavedPresetsSection(),
          const SizedBox(height: 24),
          const Text(
            'رنگ‌های برنامه',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ..._items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildColorTile(item),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ============================================================
  // دکمه ذخیره
  // ============================================================

  Widget _buildPresetActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تنظیمات رنگ',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'رنگ‌های فعلی را با یک نام ذخیره کنید تا بعداً بتوانید همه آن‌ها را یکجا اعمال کنید.',
              style: TextStyle(
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saveCurrentPreset,
              icon: const Icon(
                Icons.save_outlined,
              ),
              label: const Text(
                'ذخیره تنظیمات فعلی',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // تنظیمات ذخیره‌شده
  // ============================================================

  Widget _buildSavedPresetsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تنظیمات رنگ ذخیره‌شده',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_loadingPresets)
              const Center(
                child: CircularProgressIndicator(),
              )
            else if (_presetNames.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(
                  vertical: 12,
                ),
                child: Text(
                  'هنوز هیچ تنظیم رنگی ذخیره نشده است.',
                ),
              )
            else
              ..._presetNames.map(
                (name) => _buildPresetTile(name),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // کارت تنظیم ذخیره‌شده
  // ============================================================

  Widget _buildPresetTile(
    String name,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AppColors.getColor(
                  'background',
                ),
                AppColors.getColor(
                  'button',
                ),
              ],
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: const Text(
          'مجموعه کامل رنگ‌های برنامه',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'apply') {
              _applyPreset(name);
            }

            if (value == 'delete') {
              _deletePreset(name);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'apply',
              child: ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('اعمال'),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('حذف'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // رنگ
  // ============================================================

  Widget _buildColorTile(
    _ColorItem item,
  ) {
    final color = item.getColor();

    return Card(
      child: ListTile(
        title: Text(item.title),
        subtitle: Text(
          '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
        ),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white24,
              width: 1.5,
            ),
          ),
        ),
        trailing: const Icon(
          Icons.chevron_left,
        ),
        onTap: () => _pickColor(item),
      ),
    );
  }
}

// ================================================================
// COLOR ITEM
// ================================================================

class _ColorItem {
  final String title;
  final String key;

  const _ColorItem(
    this.title,
    this.key,
  );

  Color getColor() {
    return AppColors.getColor(key);
  }

  void setColor(Color color) {
    AppColors.setColor(
      key,
      color,
    );
  }
}

// ================================================================
// COLOR PICKER
// ================================================================

class _ColorPickerDialog extends StatefulWidget {
  final String title;
  final Color initialColor;

  const _ColorPickerDialog({
    required this.title,
    required this.initialColor,
  });

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double red;
  late double green;
  late double blue;
  late double alpha;

  @override
  void initState() {
    super.initState();

    red = widget.initialColor.r * 255;
    green = widget.initialColor.g * 255;
    blue = widget.initialColor.b * 255;
    alpha = widget.initialColor.a * 255;
  }

  Color get color {
    return Color.fromARGB(
      alpha.round(),
      red.round(),
      green.round(),
      blue.round(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              height: 80,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white24,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _slider(
              'قرمز',
              red,
              (value) {
                setState(() {
                  red = value;
                });
              },
            ),
            _slider(
              'سبز',
              green,
              (value) {
                setState(() {
                  green = value;
                });
              },
            ),
            _slider(
              'آبی',
              blue,
              (value) {
                setState(() {
                  blue = value;
                });
              },
            ),
            _slider(
              'شفافیت',
              alpha,
              (value) {
                setState(() {
                  alpha = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('لغو'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              color,
            );
          },
          child: const Text('ذخیره'),
        ),
      ],
    );
  }

  Widget _slider(
    String title,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title),
            Text(
              value.round().toString(),
            ),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: 255,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
