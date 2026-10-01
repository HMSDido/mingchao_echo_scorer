import 'package:flutter/material.dart';

import '../../core/theme/palette.dart';
import '../../data/catalog/substat_type.dart';
import 'tier_picker.dart';

/// 一条副词条的输入行，版式为「副词条属性 · 系数值 × 档位」。
///
/// 系数是只读的（在「编辑角色系数」里配置），这里仅展示，让用户一眼看出该属性
/// 按「系数 × 档位」计入本件评分。
class SubstatRow extends StatelessWidget {
  const SubstatRow({
    required this.type,
    required this.tier,
    required this.coefficient,
    required this.useDropdown,
    required this.onChanged,
    super.key,
  });

  final SubstatType type;
  final int tier;
  final double coefficient;
  final bool useDropdown;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attributeColor = AppPalette.onAccent(
      context,
      AppPalette.attribute(type),
    );
    final filled = tier > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: filled
            ? AppPalette.attributeSoft(context, type)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: filled
              ? attributeColor.withValues(alpha: 0.45)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: useDropdown
          ? Row(
              children: [
                _Label(type: type, color: attributeColor),
                const Spacer(),
                _CoefficientTimes(coefficient: coefficient),
                const SizedBox(width: 10),
                TierPicker(type: type, value: tier, onChanged: onChanged),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Label(type: type, color: attributeColor),
                    const Spacer(),
                    _CoefficientTimes(coefficient: coefficient),
                  ],
                ),
                const SizedBox(height: 8),
                TierPicker(
                  type: type,
                  value: tier,
                  onChanged: onChanged,
                  useDropdown: false,
                ),
              ],
            ),
    );
  }
}

/// 属性名（前置属性色圆点）。
class _Label extends StatelessWidget {
  const _Label({required this.type, required this.color});

  final SubstatType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          type.label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 只读的「系数值 ×」，紧挨档位选择器，与其一起读作「系数 × 档位」。
class _CoefficientTimes extends StatelessWidget {
  const _CoefficientTimes({required this.coefficient});

  final double coefficient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '系数（只读，可在「编辑角色系数」中调整）',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            coefficient.toStringAsFixed(3),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '×',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
