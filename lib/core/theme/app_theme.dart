import 'package:flutter/material.dart';

/// 由种子色生成亮/暗两套主题。
class AppTheme {
  const AppTheme._();

  /// 可选的主题种子色，用于「主题色设置」页。
  static const List<Color> seedPresets = [
    Color(0xFF6750A4), // 深紫（默认）
    Color(0xFF3369E6), // 蓝
    Color(0xFF17A2A2), // 青
    Color(0xFF2E9E5B), // 绿
    Color(0xFFE0A800), // 金
    Color(0xFFF26B1D), // 橙
    Color(0xFFE5484D), // 红
    Color(0xFFC24BA8), // 品红
    Color(0xFF5C6BC0), // 靛
    Color(0xFF795548), // 棕
    Color(0xFF607D8B), // 蓝灰
    Color(0xFF000000), // 纯黑
  ];

  static ThemeData light(Color seed) => _build(seed, Brightness.light);

  static ThemeData dark(Color seed) => _build(seed, Brightness.dark);

  static ThemeData _build(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.comfortable,
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: Color(0x1F808080)),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      dividerTheme: const DividerThemeData(space: 1, thickness: 1),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
