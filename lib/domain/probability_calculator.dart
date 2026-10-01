import '../data/catalog/substat_type.dart';
import '../data/catalog/tier_group.dart';
import '../data/models/coefficients.dart';
import '../data/models/echo_entry.dart';
import 'score_calculator.dart';

/// 达成概率的计算结果。
class ProbabilityOutcome {
  const ProbabilityOutcome(this.probability, {this.approximate = false});

  /// 概率，值域 [0, 1]。
  final double probability;

  /// 状态数超限、启用了分数分桶降精度时为 true（正常配置下恒为 false）。
  final bool approximate;

  /// 百分比显示值（2 位小数），如 `1.15`。
  double get percent => ScoreCalculator.roundTo2(probability * 100);
}

/// 目标分达成概率。
///
/// 模型（需求确认项 1 的选项②）：已输入 i 条词条后，剩下的 (5 - i) 条词条
/// **属性本身也是随机的** —— 从 (13 - i) 个未被选中的属性里等概率不放回抽取
/// (5 - i) 个，每个被抽中的属性再按自身档位分布独立摇档位。求
/// `P(当前分数 + 这 (5 - i) 条的分数和 ≥ 目标分数)`。
///
/// 直接枚举是 C(13,5) × 8^5 ≈ 4200 万种组合，不可行。这里用三层压缩把它降到
/// 毫秒级：
/// 1. **精确整数化**：档位数值最多 1 位小数、系数最多 3 位小数，选一个使全部系数
///    与目标分都变成整数的缩放因子（单位 U = 10 × scale），分数和用 int 表示，
///    DP 过程中零浮点累积误差；
/// 2. **按 (系数值, 档位组) 分组 + 组合数折叠**：系数相同的属性彼此不可区分，
///    只需记录「从该组选了 q 个」并乘以 C(m, q)，把 13 个属性压成通常 5~8 组；
/// 3. **上下界剪枝**：每个中间状态用后缀「剩余可选属性的最大/最小增益」判定，
///    必然达标的整块并入成功质量、必然不达标的直接丢弃，只有跨越目标线的
///    窄带状态需要继续展开。
class ProbabilityCalculator {
  const ProbabilityCalculator._();

  static const double _epsilon = 1e-9;

  /// 单层状态数上限；超出后按分数分桶合并以兜底（正常配置不会触发）。
  static const int _maxStatesPerLevel = 200000;

  /// 不可行状态哨兵：足够负，参与加法后仍会被剪枝判定吞掉。
  static const int _infeasible = -0x3FFFFFFFFFFFF;

  /// 计算达成概率；非 0 档位超过 5 条、或目标分非法时返回 null。
  static ProbabilityOutcome? reachProbability({
    required Map<SubstatType, int> tiers,
    required Coefficients coefficients,
    required double targetScore,
  }) {
    if (!targetScore.isFinite) return null;

    final filled = tiers.entries.where((e) => e.value > 0).length;
    if (filled > EchoEntry.maxSubstats) return null;

    final slots = EchoEntry.maxSubstats - filled;
    final currentRaw = ScoreCalculator.rawScore(tiers, coefficients);

    // 没有剩余槽位：结果是确定的。
    if (slots == 0) {
      return ProbabilityOutcome(
        currentRaw + _epsilon >= targetScore ? 1.0 : 0.0,
      );
    }

    final candidates = SubstatType.values
        .where((type) => (tiers[type] ?? 0) <= 0)
        .toList(growable: false);

    final scale = _pickScale(candidates, coefficients, targetScore);
    final coefficientInts = <SubstatType, int>{
      for (final type in candidates)
        type: (coefficients[type]! * scale).round(),
    };
    // 整数化单位 U = 10 × scale：档位数值最多 1 位小数（×10 变整数），系数最多
    // 3 位小数（×scale 变整数），于是「档位数值 × 系数」= valueInt × coefInt，
    // 其真值恰为 (分数 × U)。DP 全程用 (分数 × U) 的整数表示，零浮点累积误差。
    final currentInt = tiers.entries.fold(0, (sum, entry) {
      if (entry.value <= 0) return sum;
      final valueInt = (entry.key.valueAt(entry.value) * 10).round();
      return sum + valueInt * (coefficients[entry.key]! * scale).round();
    });
    // LHS 恒为整数，故 `LHS ≥ target×U` 等价于 `LHS ≥ ceil(target×U)`。
    final required = (targetScore * 10 * scale - _epsilon).ceil() - currentInt;
    if (required <= 0) return const ProbabilityOutcome(1.0);

    final groups = _groupByCoefficient(candidates, coefficientInts);
    final suffixMax = _suffixMaxGain(groups, slots);
    if (suffixMax[0][slots] < required) {
      return const ProbabilityOutcome(0.0);
    }

    return _runDp(
      groups: groups,
      suffixMax: suffixMax,
      slots: slots,
      required: required,
      totalCandidates: candidates.length,
    );
  }

  /// 选出能让全部候选系数与目标分同时变为整数的最小缩放因子。
  ///
  /// 缩放越小，分数和的取值网格越粗、去重越充分，DP 状态数越少。目标分按
  /// `target × 10 × scale`（即 target × U）判定，与 DP 的整数单位一致。
  static int _pickScale(
    List<SubstatType> candidates,
    Coefficients coefficients,
    double targetScore,
  ) {
    for (final scale in const [1, 10, 100, 1000]) {
      final targetOk = _isIntegral(targetScore * 10 * scale);
      if (!targetOk) continue;
      final allOk = candidates.every(
        (type) => _isIntegral(coefficients[type]! * scale),
      );
      if (allOk) return scale;
    }
    return 1000;
  }

  static bool _isIntegral(double value) =>
      value.isFinite && (value - value.roundToDouble()).abs() < 1e-6;

  static List<_CoefficientGroup> _groupByCoefficient(
    List<SubstatType> candidates,
    Map<SubstatType, int> coefficientInts,
  ) {
    final grouped = <String, _CoefficientGroup>{};
    for (final type in candidates) {
      // 增益现在取决于「档位数值」，同组（同概率分布）但数值不同的属性不再等价，
      // 因此分组键要带上 tierValues，只有系数、概率组、数值三者全同才可折叠。
      final key =
          '${coefficientInts[type]}|${type.group.name}|${type.tierValues.join(',')}';
      final existing = grouped[key];
      if (existing == null) {
        grouped[key] = _CoefficientGroup(
          coefficientInt: coefficientInts[type]!,
          group: type.group,
          valueInts: [
            for (var tier = 1; tier <= type.tierCount; tier++)
              (type.valueAt(tier) * 10).round(),
          ],
          count: 1,
        );
      } else {
        existing.count++;
      }
    }
    // 系数大的组排在前面，能让剪枝更早收紧上下界。
    final result = grouped.values.toList()
      ..sort((a, b) {
        final byCoefficient = b.coefficientInt.compareTo(a.coefficientInt);
        return byCoefficient != 0
            ? byCoefficient
            : a.group.index.compareTo(b.group.index);
      });
    return result;
  }

  /// `suffixMax[g][j]`：只从第 g 组及之后的属性里恰好选 j 个时，可获得的最大增益。
  static List<List<int>> _suffixMaxGain(
    List<_CoefficientGroup> groups,
    int slots,
  ) {
    return _suffixBound(groups, slots, isMax: true);
  }

  /// `suffixMin[g][j]`：同上，最小增益（每个被选属性按档位 1 计）。
  static List<List<int>> _suffixMinGain(
    List<_CoefficientGroup> groups,
    int slots,
  ) {
    return _suffixBound(groups, slots, isMax: false);
  }

  static List<List<int>> _suffixBound(
    List<_CoefficientGroup> groups,
    int slots, {
    required bool isMax,
  }) {
    final g = groups.length;
    final table = List.generate(
      g + 1,
      (_) => List<int>.filled(slots + 1, _infeasible),
    );
    table[g][0] = 0;

    // 每组之后的属性总数，用于限定 q 的可行范围。
    final tailCount = List<int>.filled(g + 1, 0);
    for (var i = g - 1; i >= 0; i--) {
      tailCount[i] = tailCount[i + 1] + groups[i].count;
    }

    for (var i = g - 1; i >= 0; i--) {
      final group = groups[i];
      // 档位数值升序：最大增益取最高档数值，最小增益取档位 1 的数值。
      final perPick = isMax
          ? group.coefficientInt * group.valueInts.last
          : group.coefficientInt * group.valueInts.first;
      for (var j = 0; j <= slots; j++) {
        var best = _infeasible;
        final qMin = (j - tailCount[i + 1]).clamp(0, group.count);
        final qMax = j < group.count ? j : group.count;
        for (var q = qMin; q <= qMax; q++) {
          final rest = table[i + 1][j - q];
          if (rest == _infeasible) continue;
          final value = q * perPick + rest;
          if (best == _infeasible || (isMax ? value > best : value < best)) {
            best = value;
          }
        }
        table[i][j] = best;
      }
    }
    return table;
  }

  static ProbabilityOutcome _runDp({
    required List<_CoefficientGroup> groups,
    required List<List<int>> suffixMax,
    required int slots,
    required int required,
    required int totalCandidates,
  }) {
    final suffixMin = _suffixMinGain(groups, slots);
    final suffixCount = List.generate(groups.length + 1, (g) {
      var members = 0;
      for (var i = g; i < groups.length; i++) {
        members += groups[i].count;
      }
      return List<int>.generate(slots + 1, (j) => binomial(members, j));
    });

    final denominator = binomial(totalCandidates, slots);
    if (denominator == 0) return const ProbabilityOutcome(0.0);

    var levels = List<Map<int, double>>.generate(slots + 1, (_) => {});
    levels[0][0] = 1.0;
    var certainMass = 0.0;
    var approximate = false;

    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      final transitions = group.transitions(slots);
      final next = List<Map<int, double>>.generate(slots + 1, (_) => {});

      for (var j = 0; j <= slots; j++) {
        final source = levels[j];
        if (source.isEmpty) continue;
        for (final transition in transitions) {
          final target = j + transition.picks;
          if (target > slots) continue;
          final bucket = next[target];
          final weight = transition.ways.toDouble();
          source.forEach((sum, prob) {
            final base = prob * weight;
            for (final entry in transition.gains.entries) {
              final key = sum + entry.key;
              bucket[key] = (bucket[key] ?? 0) + base * entry.value;
            }
          });
        }
      }

      // 剪枝：把「必然达标」与「必然不达标」的状态从表中摘掉。
      for (var j = 0; j <= slots; j++) {
        final level = next[j];
        if (level.isEmpty) continue;
        final remaining = slots - j;
        if (suffixCount[g + 1][remaining] == 0) {
          level.clear();
          continue;
        }
        final maxGain = suffixMax[g + 1][remaining];
        final minGain = suffixMin[g + 1][remaining];
        final certainFactor = suffixCount[g + 1][remaining].toDouble();

        if (level.length > _maxStatesPerLevel) {
          approximate = true;
          _compact(level);
        }

        level.removeWhere((sum, prob) {
          if (sum + maxGain < required) return true;
          if (sum + minGain >= required) {
            certainMass += prob * certainFactor;
            return true;
          }
          return false;
        });
      }

      levels = next;
    }

    var numerator = certainMass;
    for (final entry in levels[slots].entries) {
      if (entry.key >= required) numerator += entry.value;
    }

    final probability = (numerator / denominator).clamp(0.0, 1.0);
    return ProbabilityOutcome(probability, approximate: approximate);
  }

  /// 状态数超限时按分数分桶合并（向下取整到 bucket 的倍数）。
  ///
  /// 只在极端配置下触发；分桶后成功判定偏保守，误差 ≤ 一个 bucket。
  static void _compact(Map<int, double> level) {
    for (final bucket in const [10, 100, 1000, 10000]) {
      final merged = <int, double>{};
      level.forEach((sum, prob) {
        final key = (sum ~/ bucket) * bucket;
        merged[key] = (merged[key] ?? 0) + prob;
      });
      level
        ..clear()
        ..addAll(merged);
      if (level.length <= _maxStatesPerLevel) return;
    }
  }

  static final Map<int, List<int>> _binomials = {};

  /// 组合数 C(n, k)；n ≤ 13，int 精确无溢出。
  static int binomial(int n, int k) {
    if (k < 0 || k > n) return 0;
    final row = _binomials.putIfAbsent(n, () {
      final values = List<int>.filled(n + 1, 1);
      for (var i = 1; i <= n; i++) {
        values[i] = values[i - 1] * (n - i + 1) ~/ i;
      }
      return values;
    });
    return row[k];
  }
}

/// 一组「系数、档位概率分布、档位数值都相同」的候选属性。
class _CoefficientGroup {
  _CoefficientGroup({
    required this.coefficientInt,
    required this.group,
    required this.valueInts,
    required this.count,
  });

  final int coefficientInt;
  final TierGroup group;

  /// 各档位（1 起）数值 ×10 取整，下标 0 对应档位 1；升序。
  final List<int> valueInts;
  int count;

  final Map<int, List<_GroupTransition>> _cache = {};

  /// 从本组选 q 个属性时的转移表（q = 0..maxPicks）。
  List<_GroupTransition> transitions(int maxPicks) => _cache.putIfAbsent(
    maxPicks,
    () => [
      for (var q = 0; q <= (count < maxPicks ? count : maxPicks); q++)
        _GroupTransition(
          picks: q,
          ways: ProbabilityCalculator.binomial(count, q),
          gains: _gainDistribution(q),
        ),
    ],
  );

  /// q 次独立摇档位的「分数增益 → 概率」分布。
  ///
  /// 增益 = 档位数值 ×10 × 系数 ×scale（即 分数 × U）；系数为 0 时全部增益都落到
  /// 0，分布自动塌缩成 `{0: 1.0}`。
  Map<int, double> _gainDistribution(int q) {
    final cacheKey = '${group.name}|$coefficientInt|${valueInts.join(',')}|$q';
    final cached = _gainDistributions[cacheKey];
    if (cached != null) return cached;

    final single = <int, double>{};
    for (var tier = 1; tier <= group.tierCount; tier++) {
      final key = valueInts[tier - 1] * coefficientInt;
      single[key] = (single[key] ?? 0) + group.probabilityOf(tier);
    }

    var distribution = <int, double>{0: 1.0};
    for (var i = 0; i < q; i++) {
      final next = <int, double>{};
      distribution.forEach((sum, prob) {
        single.forEach((gain, gainProb) {
          final key = sum + gain;
          next[key] = (next[key] ?? 0) + prob * gainProb;
        });
      });
      distribution = next;
    }

    _gainDistributions[cacheKey] = distribution;
    return distribution;
  }

  static final Map<String, Map<int, double>> _gainDistributions = {};
}

class _GroupTransition {
  const _GroupTransition({
    required this.picks,
    required this.ways,
    required this.gains,
  });

  /// 从该组选中的属性数。
  final int picks;

  /// 组合数 C(m, picks)。
  final int ways;

  /// 分数增益 → 概率。
  final Map<int, double> gains;
}
