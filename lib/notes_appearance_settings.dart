import 'dart:convert';

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

class NotesAppearanceSettings {
  static const _colorsKey = 'notes_appearance_colors_v1';
  static const _fontsKey = 'notes_appearance_fonts_v1';

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
