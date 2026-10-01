import '../data/catalog/substat_type.dart';
import '../data/models/coefficients.dart';
import '../data/models/echo_entry.dart';
import 'score_calculator.dart';

/// 预期最高分的计算结果。
class ExpectedMax {
  const ExpectedMax({
    required this.value,
    required this.filledCount,
    required this.remainingSlots,
    required this.bestRemaining,
  });

  /// 预期最高分（2 位小数）。
  final double value;

  /// 已输入的非 0 档位词条数。
  final int filledCount;

  /// 剩余可开出的词条数 = 5 - [filledCount]。
  final int remainingSlots;

  /// 剩余槽位按 `系数 × 最高档位数值` 降序选中的属性，用于界面提示「还差哪几条」。
  final List<SubstatType> bestRemaining;
}

/// 预期最高分：已输入 i 条词条时，在剩下的 (13 - i) 个**未被选择过**的属性中，
/// 取 `系数 × 最高档位数值` 最大的 (5 - i) 项（不放回、互异），其分数和加上当前分数。
class ExpectedMaxCalculator {
  const ExpectedMaxCalculator._();

  /// 非 0 档位超过 5 条时返回 null（此时界面不输出结果并提示）。
  static ExpectedMax? calculate({
    required Map<SubstatType, int> tiers,
    required Coefficients coefficients,
  }) {
    final filled = tiers.entries.where((e) => e.value > 0).length;
    if (filled > EchoEntry.maxSubstats) return null;

    final remainingSlots = EchoEntry.maxSubstats - filled;
    final unselected = SubstatType.values.where(
      (type) => (tiers[type] ?? 0) <= 0,
    );

    final ranked = unselected.toList()
      ..sort((a, b) {
        final gainA = coefficients[a]! * a.maxValue;
        final gainB = coefficients[b]! * b.maxValue;
        final byGain = gainB.compareTo(gainA);
        // 增益相同（尤其全为 0）时按枚举顺序稳定排序，保证结果可复现。
        return byGain != 0 ? byGain : a.index.compareTo(b.index);
      });
    final best = ranked.take(remainingSlots).toList(growable: false);

    final currentRaw = ScoreCalculator.rawScore(tiers, coefficients);
    final bestRaw = best.fold(
      0.0,
      (sum, type) => sum + coefficients[type]! * type.maxValue,
    );

    return ExpectedMax(
      value: ScoreCalculator.roundTo2(currentRaw + bestRaw),
      filledCount: filled,
      remainingSlots: remainingSlots,
      bestRemaining: best,
    );
  }
}
