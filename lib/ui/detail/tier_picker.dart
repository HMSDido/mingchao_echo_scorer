import 'package:flutter/material.dart';

import '../../core/theme/palette.dart';
import '../../core/util/format.dart';
import '../../data/catalog/substat_type.dart';

/// 档位选择器：档位 0（尚未开出）+ 该属性的全部档位。
///
/// [useDropdown] 为 true 时用下拉框（宽屏），否则用一行可选标签（窄屏）。
class TierPicker extends StatelessWidget {
  const TierPicker({
    required this.type,
    required this.value,
    required this.onChanged,
    this.useDropdown = true,
    super.key,
  });

  final SubstatType type;
  final int value;
  final ValueChanged<int> onChanged;
  final bool useDropdown;

  static String tierLabel(SubstatType type, int tier) => tier == 0
      ? '0档 · 未开出'
      : '$tier档 · ${type.displayValueOf(tier)} · '
            '${Format.tierProbability(type.probabilityOf(tier))}';

  @override
  Widget build(BuildContext context) => useDropdown
      ? _Dropdown(type: type, value: value, onChanged: onChanged)
      : _Chips(type: type, value: value, onChanged: onChanged);
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.type,
    required this.value,
    required this.onChanged,
  });

  final SubstatType type;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppPalette.tier(value).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppPalette.tier(value).withValues(alpha: 0.6),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(10),
          icon: Icon(Icons.arrow_drop_down, color: AppPalette.tier(value)),
          items: [
            for (var tier = 0; tier <= type.maxTier; tier++)
              DropdownMenuItem(
                value: tier,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppPalette.tier(tier),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      TierPicker.tierLabel(type, tier),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: tier == value
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (next) => onChanged(next ?? 0),
        ),
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({
    required this.type,
    required this.value,
    required this.onChanged,
  });

  final SubstatType type;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var tier = 0; tier <= type.maxTier; tier++)
          ChoiceChip(
            label: Text(
              tier == 0 ? '0' : '$tier档 ${type.displayValueOf(tier)}',
            ),
            selected: tier == value,
            visualDensity: VisualDensity.compact,
            selectedColor: AppPalette.tier(tier).withValues(alpha: 0.28),
            side: BorderSide(
              color: tier == value
                  ? AppPalette.tier(tier)
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
            onSelected: (_) => onChanged(tier),
          ),
      ],
    );
  }
}
