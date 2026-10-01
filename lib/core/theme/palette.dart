import 'package:flutter/material.dart';

import '../../data/catalog/substat_type.dart';
import '../../data/models/rating.dart';

/// 评级、副词条属性、档位的配色。
///
/// 需求要求三者「以不同颜色区分」：评级用一组固定的等级色，属性用 13 种互不相近
/// 的色相，档位用一条从冷到暖的递进色带（档位越高越暖）。
class AppPalette {
  const AppPalette._();

  static const Map<Rating, Color> _ratingColors = {
    Rating.ace: Color(0xFFD99A00),
    Rating.s: Color(0xFFA44FD9),
    Rating.a: Color(0xFF3369E6),
    Rating.b: Color(0xFF2E9E5B),
    Rating.c: Color(0xFFD2762B),
    Rating.none: Color(0xFF8C8C8C),
  };

  /// 顺序与 [SubstatType.values] 严格对应。
  static const List<Color> _attributeColors = [
    Color(0xFFE5484D), // 暴击率
    Color(0xFFF26B1D), // 暴击伤害
    Color(0xFFE0A800), // 攻击%
    Color(0xFF7CB342), // 生命%
    Color(0xFF2E9E5B), // 防御%
    Color(0xFF17A2A2), // 普攻伤害加成
    Color(0xFF2196C8), // 重击伤害加成
    Color(0xFF4A6FD4), // 共鸣技能伤害加成
    Color(0xFF7B52D1), // 共鸣解放伤害加成
    Color(0xFFC24BA8), // 共鸣效率
    Color(0xFFA9714B), // 固定攻击
    Color(0xFF6E9C8F), // 固定生命
    Color(0xFF8A8F98), // 固定防御
  ];

  /// 下标即档位序号，0 为「尚未开出」。覆盖到 8 档（当前最大档位数）。
  static const List<Color> _tierColors = [
    Color(0xFF9E9E9E), // 0 未开出
    Color(0xFF8FA6B2),
    Color(0xFF6FBFB2),
    Color(0xFF66BB6A),
    Color(0xFFB7C22F),
    Color(0xFFFFC107),
    Color(0xFFFF9800),
    Color(0xFFFF7043),
    Color(0xFFE5484D),
  ];

  static Color rating(Rating rating) =>
      _ratingColors[rating] ?? _ratingColors[Rating.none]!;

  static Color attribute(SubstatType type) =>
      _attributeColors[type.index % _attributeColors.length];

  static Color tier(int tier) =>
      _tierColors[tier.clamp(0, _tierColors.length - 1)];

  /// 在深浅两种主题下都可读的语义色（用于文字与图标）。
  static Color onAccent(BuildContext context, Color color) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? Color.alphaBlend(color.withValues(alpha: 0.55), Colors.white)
        : color;
  }

  /// 属性的浅色背景（选中态、标签底色）。
  static Color attributeSoft(BuildContext context, SubstatType type) =>
      attribute(type).withValues(alpha: 0.16);
}
