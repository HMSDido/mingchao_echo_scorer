import 'tier_group.dart';

/// 词条数值的显示单位。
enum SubstatUnit {
  /// 显示为百分比，如 `6.3%`。
  percent,

  /// 显示为整数，如 `320`。
  flat,
}

/// 13 种副词条属性。
///
/// 枚举顺序即 UI 中的展示顺序，与需求文档一致。
enum SubstatType {
  critRate(
    label: '暴击率',
    group: TierGroup.crit,
    unit: SubstatUnit.percent,
    tierValues: [6.3, 6.9, 7.5, 8.1, 8.7, 9.3, 9.9, 10.5],
  ),
  critDmg(
    label: '暴击伤害',
    group: TierGroup.crit,
    unit: SubstatUnit.percent,
    tierValues: [12.6, 13.8, 15.0, 16.2, 17.4, 18.6, 19.8, 21.0],
  ),
  atkPct(
    label: '攻击%',
    group: TierGroup.percentLike,
    unit: SubstatUnit.percent,
    tierValues: [6.4, 7.1, 7.9, 8.6, 9.4, 10.1, 10.9, 11.6],
  ),
  hpPct(
    label: '生命%',
    group: TierGroup.percentLike,
    unit: SubstatUnit.percent,
    tierValues: [6.4, 7.1, 7.9, 8.6, 9.4, 10.1, 10.9, 11.6],
  ),
  defPct(
    label: '防御%',
    group: TierGroup.percentLike,
    unit: SubstatUnit.percent,
    tierValues: [8.1, 9.0, 10.0, 10.9, 11.8, 12.8, 13.8, 14.7],
  ),
  basicAtkBonus(
    label: '普攻伤害加成',
    group: TierGroup.percentLike,
    unit: SubstatUnit.percent,
    tierValues: [6.4, 7.1, 7.9, 8.6, 9.4, 10.1, 10.9, 11.6],
  ),
  heavyAtkBonus(
    label: '重击伤害加成',
    group: TierGroup.percentLike,
    unit: SubstatUnit.percent,
    tierValues: [6.4, 7.1, 7.9, 8.6, 9.4, 10.1, 10.9, 11.6],
  ),
  skillBonus(
    label: '共鸣技能伤害加成',
    group: TierGroup.percentLike,
    unit: SubstatUnit.percent,
    tierValues: [6.4, 7.1, 7.9, 8.6, 9.4, 10.1, 10.9, 11.6],
  ),
  liberationBonus(
    label: '共鸣解放伤害加成',
    group: TierGroup.percentLike,
    unit: SubstatUnit.percent,
    tierValues: [6.4, 7.1, 7.9, 8.6, 9.4, 10.1, 10.9, 11.6],
  ),
  energyRegen(
    label: '共鸣效率',
    group: TierGroup.percentLike,
    unit: SubstatUnit.percent,
    tierValues: [6.8, 7.6, 8.4, 9.2, 10.0, 10.8, 11.6, 12.4],
  ),
  flatAtk(
    label: '固定攻击',
    group: TierGroup.flatAtk,
    unit: SubstatUnit.flat,
    tierValues: [30, 40, 50, 60],
  ),
  flatHp(
    label: '固定生命',
    group: TierGroup.percentLike,
    unit: SubstatUnit.flat,
    tierValues: [320, 360, 390, 430, 470, 510, 540, 580],
  ),
  flatDef(
    label: '固定防御',
    group: TierGroup.flatDef,
    unit: SubstatUnit.flat,
    tierValues: [40, 50, 60, 70],
  );

  const SubstatType({
    required this.label,
    required this.group,
    required this.unit,
    required this.tierValues,
  });

  /// 中文显示名。
  final String label;

  /// 所属档位概率组。
  final TierGroup group;

  /// 数值显示单位。
  final SubstatUnit unit;

  /// 各档位的属性数值，下标 0 对应档位 1。长度必须等于 [TierGroup.tierCount]。
  final List<double> tierValues;

  /// 档位数（不含档位 0）。
  int get tierCount => group.tierCount;

  /// 最高档位序号。
  int get maxTier => group.tierCount;

  /// 档位 [tier]（1 起）的概率。
  double probabilityOf(int tier) => group.probabilityOf(tier);

  /// 档位 [tier]（1 起）的属性数值。
  ///
  /// 百分比属性返回去掉 `%` 后的数字（如 `6.3%` → `6.3`），固定值属性返回原值
  /// （如 `430`）。评分一律用该数值 × 系数，而不是用档位序号。
  double valueAt(int tier) {
    assert(tier >= 1 && tier <= tierCount, 'tier $tier 超出 $name 的范围');
    return tierValues[tier - 1];
  }

  /// 最高档位（[maxTier]）的属性数值。
  double get maxValue => tierValues[tierCount - 1];

  /// 档位 [tier]（1 起）的显示文本，如 `7.5%` 或 `430`。
  String displayValueOf(int tier) {
    assert(tier >= 1 && tier <= tierCount, 'tier $tier 超出 $name 的范围');
    final value = tierValues[tier - 1];
    return unit == SubstatUnit.percent
        ? '${value.toStringAsFixed(1)}%'
        : value.toStringAsFixed(0);
  }

  /// 多件声骸合计值的显示文本：百分比属性保留 1 位小数并带 `%`，固定值取整。
  String displaySumOf(double value) => unit == SubstatUnit.percent
      ? '${value.toStringAsFixed(1)}%'
      : value.toStringAsFixed(0);

  /// JSON 序列化用的稳定键名（英文，不随中文名变动）。
  String get jsonKey => name;

  /// 按 [jsonKey] 反查；未知键返回 null（向前兼容）。
  static SubstatType? fromJsonKey(String key) {
    for (final type in values) {
      if (type.name == key) return type;
    }
    return null;
  }
}
