import '../data/catalog/substat_type.dart';
import '../data/models/coefficients.dart';
import '../data/models/echo_entry.dart';
import '../data/models/rating.dart';

/// 单件声骸的评分结果（派生值，不落盘）。
class EchoScore {
  const EchoScore({
    required this.raw,
    required this.score,
    required this.maxScore,
    required this.rating,
    required this.filledCount,
    required this.isOverFilled,
  });

  /// 全精度原始分：Σ(档位数值 × 系数)，未取整。
  final double raw;

  /// 显示分：[raw] 四舍五入到 2 位小数。
  final double score;

  /// 单件声骸理论最高分（2 位小数）。
  final double maxScore;

  final Rating rating;

  /// 已开出的非 0 档位词条数。
  final int filledCount;

  /// 非 0 档位超过 5 条：此时按需求不输出任何结果。
  final bool isOverFilled;

  double get ratio => maxScore <= 0 ? 0.0 : score / maxScore;
}

/// 整份评分文件的汇总结果（派生值，不落盘）。
class FileScore {
  const FileScore({
    required this.totalScore,
    required this.totalMaxScore,
    required this.totalRating,
    required this.echoes,
  });

  /// 5 件声骸显示分之和（2 位小数）。
  final double totalScore;

  /// 总理论最高分 = 5 × 单件理论最高分。
  final double totalMaxScore;

  final Rating totalRating;

  final List<EchoScore> echoes;

  double get ratio => totalMaxScore <= 0 ? 0.0 : totalScore / totalMaxScore;
}

/// 评分与评级计算。
///
/// 约定（对应需求确认项）：
/// * 各词条 `档位数值 × 系数` 以全精度累加，**最后**统一四舍五入到 2 位小数；
///   档位数值取自内置档位表（百分比属性去掉 `%`，如 `7.5%` 记作 `7.5`），
///   **不是**档位序号；
/// * 评级比值使用「已取整的显示分 / 理论最高分」，保证界面上的分数与评级自洽；
/// * 单件理论最高分 = 13 项 `系数 × 该属性最高档位数值` 降序取前 5 之和；
/// * 总理论最高分 = 5 × 单件理论最高分。
class ScoreCalculator {
  const ScoreCalculator._();

  /// 四舍五入到 2 位小数。
  static double roundTo2(double value) => (value * 100).roundToDouble() / 100;

  /// 全精度原始分。
  static double rawScore(
    Map<SubstatType, int> tiers,
    Coefficients coefficients,
  ) {
    var sum = 0.0;
    tiers.forEach((type, tier) {
      if (tier <= 0) return;
      sum += type.valueAt(tier) * coefficients[type]!;
    });
    return sum;
  }

  /// 从 [candidates] 中取 `系数 × 最高档位数值` 最大的前 [count] 项之和（不放回）。
  ///
  /// 同时服务于「理论最高分」（candidates = 全部 13 项，count = 5）
  /// 与「预期最高分」（candidates = 未选中的属性，count = 5 - 已输入数）。
  static double topGain(
    Iterable<SubstatType> candidates,
    Coefficients coefficients,
    int count,
  ) {
    if (count <= 0) return 0.0;
    final gains =
        candidates.map((type) => coefficients[type]! * type.maxValue).toList()
          ..sort((a, b) => b.compareTo(a));
    var sum = 0.0;
    for (var i = 0; i < count && i < gains.length; i++) {
      sum += gains[i];
    }
    return sum;
  }

  /// 单件声骸理论最高分（全精度）。
  static double echoMaxRaw(Coefficients coefficients) =>
      topGain(SubstatType.values, coefficients, EchoEntry.maxSubstats);

  static EchoScore scoreEcho(EchoEntry echo, Coefficients coefficients) {
    final filled = echo.filledCount;
    final overFilled = filled > EchoEntry.maxSubstats;
    final maxRaw = echoMaxRaw(coefficients);
    final maxScore = roundTo2(maxRaw);
    if (overFilled) {
      return EchoScore(
        raw: 0,
        score: 0,
        maxScore: maxScore,
        rating: Rating.none,
        filledCount: filled,
        isOverFilled: true,
      );
    }
    final raw = rawScore(echo.tiers, coefficients);
    final score = roundTo2(raw);
    return EchoScore(
      raw: raw,
      score: score,
      maxScore: maxScore,
      rating: Rating.fromScore(score, maxScore),
      filledCount: filled,
      isOverFilled: false,
    );
  }

  static FileScore scoreFile(
    List<EchoEntry> echoes,
    Coefficients coefficients,
  ) {
    final scores = echoes
        .map((echo) => scoreEcho(echo, coefficients))
        .toList(growable: false);
    final total = roundTo2(scores.fold(0.0, (sum, item) => sum + item.score));
    final totalMax = roundTo2(
      scores.isEmpty ? 0.0 : scores.first.maxScore * EchoEntry.slotCount,
    );
    return FileScore(
      totalScore: total,
      totalMaxScore: totalMax,
      totalRating: Rating.fromScore(total, totalMax),
      echoes: scores,
    );
  }
}
