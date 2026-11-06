import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotesFontSettings {
  final String appFontFamily;
  final double appTextSize;
  final String inputFontFamily;
  final double inputTextSize;

  const NotesFontSettings({
    this.appFontFamily = 'Roboto',
    this.appTextSize = 14,
    this.inputFontFamily = 'Roboto',
    this.inputTextSize = 15,
  });

  NotesFontSettings copyWith({
    String? appFontFamily,
    double? appTextSize,
    String? inputFontFamily,
    double? inputTextSize,
  }) =>
      NotesFontSettings(
        appFontFamily: appFontFamily ?? this.appFontFamily,
        appTextSize: appTextSize ?? this.appTextSize,
        inputFontFamily: inputFontFamily ?? this.inputFontFamily,
        inputTextSize: inputTextSize ?? this.inputTextSize,
      );

  Map<String, dynamic> toJson() => {
        'appFontFamily': appFontFamily,
        'appTextSize': appTextSize,
        'inputFontFamily': inputFontFamily,
        'inputTextSize': inputTextSize,
      };

  factory NotesFontSettings.fromJson(Map<String, dynamic> json) =>
      NotesFontSettings(
        appFontFamily: (json['appFontFamily'] ?? 'Roboto').toString(),
        appTextSize: (json['appTextSize'] as num?)?.toDouble() ?? 14,
        inputFontFamily: (json['inputFontFamily'] ?? 'Roboto').toString(),
        inputTextSize: (json['inputTextSize'] as num?)?.toDouble() ?? 15,
      );
}


class NoteTextTheme {
  final String id;
  final String name;
  final int backgroundColor;
  final int textColor;
  final String fontFamily;
  final double fontSize;

  const NoteTextTheme({
    required this.id,
    required this.name,
    required this.backgroundColor,
    required this.textColor,
    required this.fontFamily,
    required this.fontSize,
  });

  Color get background => Color(backgroundColor);
  Color get foreground => Color(textColor);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'backgroundColor': backgroundColor,
        'textColor': textColor,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
      };

  factory NoteTextTheme.fromJson(Map<String, dynamic> json) => NoteTextTheme(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? 'قالب').toString(),
        backgroundColor: (json['backgroundColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
        textColor: (json['textColor'] as num?)?.toInt() ?? 0xFF222222,
        fontFamily: (json['fontFamily'] ?? 'Roboto').toString(),
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 15,
      );
}

class NotesAppearanceSettings {
  static const _colorsKey = 'notes_appearance_colors_v1';
  static const _fontsKey = 'notes_appearance_fonts_v1';
  static const _themesKey = 'notes_text_themes_v1';

  static const List<NoteTextTheme> builtInThemes = [
    NoteTextTheme(id: 'classic', name: 'کلاسیک', backgroundColor: 0xFFFFFFFF, textColor: 0xFF202124, fontFamily: 'Roboto', fontSize: 15),
    NoteTextTheme(id: 'midnight', name: 'شب', backgroundColor: 0xFF17212B, textColor: 0xFFE6EDF3, fontFamily: 'Roboto', fontSize: 15),
    NoteTextTheme(id: 'mint', name: 'نعنایی', backgroundColor: 0xFFE8F5E9, textColor: 0xFF1B4332, fontFamily: 'Roboto', fontSize: 16),
    NoteTextTheme(id: 'rose', name: 'رز', backgroundColor: 0xFFFFEEF2, textColor: 0xFF7F1D3A, fontFamily: 'Roboto', fontSize: 16),
    NoteTextTheme(id: 'sand', name: 'کاغذی', backgroundColor: 0xFFFFF3D6, textColor: 0xFF493B27, fontFamily: 'Roboto', fontSize: 16),
    NoteTextTheme(id: 'blue', name: 'آبی', backgroundColor: 0xFFEAF2FF, textColor: 0xFF17365D, fontFamily: 'Roboto', fontSize: 15),
  ];
  static final ValueNotifier<List<NoteTextTheme>> customThemes = ValueNotifier<List<NoteTextTheme>>([]);

  static List<NoteTextTheme> get allThemes => [...builtInThemes, ...customThemes.value];

  static NoteTextTheme themeById(String? id) => allThemes.firstWhere(
        (theme) => theme.id == id,
        orElse: () => builtInThemes.first,
      );

  static String randomThemeId() {
    final themes = allThemes;
    return themes[math.Random().nextInt(themes.length)].id;
  }

  static Future<void> saveCustomTheme(NoteTextTheme theme) async {
    final next = [...customThemes.value.where((item) => item.id != theme.id), theme];
    customThemes.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themesKey, jsonEncode(next.map((item) => item.toJson()).toList()));
  }

  static Future<void> deleteCustomTheme(String id) async {
    customThemes.value = customThemes.value.where((item) => item.id != id).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themesKey, jsonEncode(customThemes.value.map((item) => item.toJson()).toList()));
  }

  static final Map<String, Color> _defaults = {
    'pageBackground': const Color(0xFF0D1117),
    'appBarBackground': const Color(0xFF161B22),
    'appBarText': Colors.white,
    'appBarIcon': Colors.white,
    'cardBackground': const Color(0xFF161B22),
    'primaryText': const Color(0xFFE6EDF3),
    'secondaryText': const Color(0xFF9DA7B3),
    'icon': const Color(0xFF58A6FF),
    'divider': const Color(0xFF30363D),
    'inputBackground': const Color(0xFF21262D),
    'inputBorder': const Color(0xFF30363D),
    'inputText': Colors.white,
    'hintText': const Color(0xFF8B949E),
    'buttonBackground': const Color(0xFF238636),
    'buttonText': Colors.white,
    'floatingButtonBackground': const Color(0xFF238636),
    'floatingButtonText': Colors.white,
    'dialogBackground': const Color(0xFF161B22),
    'menuBackground': const Color(0xFF21262D),
    'snackbarBackground': const Color(0xFF30363D),
    'snackbarText': Colors.white,
    'toolbarBackground': const Color(0xFF21262D),
    'recording': const Color(0xFFFF6B6B),
    'delete': const Color(0xFFFF6B6B),
  };

  static final ValueNotifier<Map<String, Color>> colors =
      ValueNotifier<Map<String, Color>>(Map<String, Color>.from(_defaults));
  static final ValueNotifier<NotesFontSettings> fonts =
      ValueNotifier<NotesFontSettings>(const NotesFontSettings());

  static Color color(String key) =>
      colors.value[key] ?? _defaults[key] ?? Colors.white;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawColors = prefs.getString(_colorsKey);
    if (rawColors != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(rawColors) as Map);
        final next = Map<String, Color>.from(_defaults);
        decoded.forEach((key, value) {
          if (next.containsKey(key) && value is int) {
            next[key] = Color(value);
          }
        });
        colors.value = next;
      } catch (_) {
        colors.value = Map<String, Color>.from(_defaults);
      }
    }
    final rawThemes = prefs.getString(_themesKey);
    if (rawThemes != null) {
      try {
        customThemes.value = (jsonDecode(rawThemes) as List)
            .map((item) => NoteTextTheme.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      } catch (_) {
        customThemes.value = [];
      }
    }
    final rawFonts = prefs.getString(_fontsKey);
    if (rawFonts != null) {
      try {
        fonts.value = NotesFontSettings.fromJson(
            Map<String, dynamic>.from(jsonDecode(rawFonts) as Map));
      } catch (_) {
        fonts.value = const NotesFontSettings();
      }
    }
  }

  static Future<void> setColor(String key, Color value) async {
    if (!_defaults.containsKey(key)) return;
    final next = Map<String, Color>.from(colors.value)..[key] = value;
    colors.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _colorsKey, jsonEncode(next.map((k, v) => MapEntry(k, v.value))));
  }

  static Future<void> setFonts(NotesFontSettings value) async {
    fonts.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontsKey, jsonEncode(value.toJson()));
  }

  static Future<void> reset() async {
    colors.value = Map<String, Color>.from(_defaults);
    fonts.value = const NotesFontSettings();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_colorsKey);
    await prefs.remove(_fontsKey);
  }

  static List<String> get colorKeys => _defaults.keys.toList(growable: false);
}
