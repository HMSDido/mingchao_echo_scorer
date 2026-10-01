import '../catalog/substat_type.dart';
import 'json_format.dart';

/// 一个声骸槽位（0..4）的录入数据。
///
/// 只保存「输入」，分数/评级/预期最高分/概率全部实时派生，不落盘。
class EchoEntry {
  const EchoEntry({
    required this.slot,
    required this.name,
    this.tiers = const {},
    this.targetScore,
  });

  factory EchoEntry.create(int slot) =>
      EchoEntry(slot: slot, name: defaultNameOf(slot));

  /// 槽位序号，取值 0..4。
  final int slot;

  /// 声骸名称，默认「声骸1」..「声骸5」，允许用户重命名。
  final String name;

  /// 已开出的档位，键为属性、值为档位序号（≥1）。
  ///
  /// 档位 0（未开出）不入表，[tierOf] 对缺失键返回 0。
  final Map<SubstatType, int> tiers;

  /// 目标分数（2 位小数），为 null 表示未设置，此时不计算达成概率。
  final double? targetScore;

  static String defaultNameOf(int slot) => '声骸${slot + 1}';

  /// 一件评分文件里的声骸槽位总数。
  static const int slotCount = 5;

  /// 单件声骸最多可开出的副词条数。
  static const int maxSubstats = 5;

  int tierOf(SubstatType type) => tiers[type] ?? 0;

  /// 已开出的（非 0 档位）词条数。
  int get filledCount => tiers.length;

  /// 是否违反「至多 5 条非 0 档位」的约束。
  bool get isOverFilled => filledCount > maxSubstats;

  EchoEntry copyWith({
    String? name,
    Map<SubstatType, int>? tiers,
    double? targetScore,
    bool clearTargetScore = false,
  }) => EchoEntry(
    slot: slot,
    name: name ?? this.name,
    tiers: tiers ?? this.tiers,
    targetScore: clearTargetScore ? null : (targetScore ?? this.targetScore),
  );

  /// 设置某属性档位；档位 0 表示清除该词条。返回新对象。
  EchoEntry withTier(SubstatType type, int tier) {
    final next = Map<SubstatType, int>.from(tiers);
    if (tier <= 0) {
      next.remove(type);
    } else {
      next[type] = tier > type.maxTier ? type.maxTier : tier;
    }
    return copyWith(tiers: next);
  }

  /// 录入内容是否一致（忽略对象身份）。
  ///
  /// 用于「像 Word 一样」判断有没有改动：没改动就不提示保存。
  bool sameContentAs(EchoEntry other) {
    if (slot != other.slot || name != other.name) return false;
    if (!_sameDouble(targetScore, other.targetScore)) return false;
    if (tiers.length != other.tiers.length) return false;
    for (final entry in tiers.entries) {
      if (other.tiers[entry.key] != entry.value) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'slot': slot,
    'name': name,
    'tiers': tiersToJson(tiers),
    if (targetScore != null) 'targetScore': targetScore,
  };

  static EchoEntry fromJson(Map<String, dynamic> json, int fallbackSlot) {
    final rawSlot = json['slot'];
    final slot = rawSlot is int && rawSlot >= 0 && rawSlot < slotCount
        ? rawSlot
        : fallbackSlot;
    final name = json['name'];
    final target = json['targetScore'];
    return EchoEntry(
      slot: slot,
      name: name is String && name.trim().isNotEmpty
          ? name.trim()
          : defaultNameOf(slot),
      tiers: tiersFromJson(json['tiers']),
      targetScore: target is num ? target.toDouble() : null,
    );
  }
}

/// NaN 与自身不相等，直接 `==` 会让含 NaN 的目标分永远判定为「已改动」。
bool _sameDouble(double? a, double? b) {
  if (a == null || b == null) return a == null && b == null;
  if (a.isNaN && b.isNaN) return true;
  return (a - b).abs() < 1e-9;
}
