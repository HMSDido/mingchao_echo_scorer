import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/data/catalog/substat_type.dart';
import 'package:mingchao_echo_scorer/data/models/coefficients.dart';
import 'package:mingchao_echo_scorer/domain/probability_calculator.dart';

void main() {
  // 评分模型：分数 = 档位数值 × 系数（百分比属性按去掉 % 的数值计）。
  // 下面把目标分直接设成「某档位数值」，因为档位数值随档位单调递增，
  // 「分数 ≥ 档位数值 k」等价于「档位 ≥ k」，概率与旧模型逐档一致。

  // 只有暴击率 = 1.0（暴击组，8 档，档位数值 6.3..10.5，档位 8 概率 3/100）
  final critOnly = normalizeCoefficients({SubstatType.critRate: 1.0});

  // 只有固定攻击 = 1.0（4 档，档位数值 30/40/50/60，档位 4 概率 3/103）
  final flatAtkOnly = normalizeCoefficients({SubstatType.flatAtk: 1.0});

  // 只有攻击% = 1.0（百分比组，8 档，档位数值 6.4..11.6）
  final atkPctOnly = normalizeCoefficients({SubstatType.atkPct: 1.0});

  // 5 条主属性各 1.0
  final fiveStats = normalizeCoefficients({
    SubstatType.critRate: 1.0,
    SubstatType.critDmg: 1.0,
    SubstatType.atkPct: 1.0,
    SubstatType.hpPct: 1.0,
    SubstatType.defPct: 1.0,
  });

  double percent(ProbabilityOutcome? outcome) {
    expect(outcome, isNotNull);
    return outcome!.percent;
  }

  group('模型②：剩余词条的属性与档位都随机', () {
    test('i=0、只有暴击率有系数：概率被「能否抽到该属性」稀释', () {
      // 抽中暴击率的概率 = C(12,4)/C(13,5) = 5/13；档位 8（10.5）概率 = 3/100
      expect(
        percent(
          ProbabilityCalculator.reachProbability(
            tiers: const {},
            coefficients: critOnly,
            targetScore: 10.5,
          ),
        ),
        1.15, // (5/13)×(3/100) = 1.1538%
      );
      // 档位 ≥7（≥9.9）→ 6/100
      expect(
        percent(
          ProbabilityCalculator.reachProbability(
            tiers: const {},
            coefficients: critOnly,
            targetScore: 9.9,
          ),
        ),
        2.31, // (5/13)×(6/100) = 2.3077%
      );
      // 只要抽中暴击率即可（任意档位 ≥1，即 ≥6.3）
      expect(
        percent(
          ProbabilityCalculator.reachProbability(
            tiers: const {},
            coefficients: critOnly,
            targetScore: 6.3,
          ),
        ),
        38.46, // 5/13
      );
      // 目标 ≤ 当前分 → 必然达成
      expect(
        percent(
          ProbabilityCalculator.reachProbability(
            tiers: const {},
            coefficients: critOnly,
            targetScore: 0.0,
          ),
        ),
        100.0,
      );
      // 超过理论上限（暴击率最高 10.5）→ 0
      expect(
        percent(
          ProbabilityCalculator.reachProbability(
            tiers: const {},
            coefficients: critOnly,
            targetScore: 11.0,
          ),
        ),
        0.0,
      );
    });

    test('暴击组用 3/100，百分比组用 3/103', () {
      final fromCrit = ProbabilityCalculator.reachProbability(
        tiers: const {},
        coefficients: critOnly,
        targetScore: 10.5,
      )!;
      final fromPercent = ProbabilityCalculator.reachProbability(
        tiers: const {},
        coefficients: atkPctOnly,
        targetScore: 11.6,
      )!;
      expect(fromCrit.probability, closeTo(5 / 13 * 3 / 100, 1e-12));
      expect(fromPercent.probability, closeTo(5 / 13 * 3 / 103, 1e-12));
      expect(fromPercent.percent, 1.12);
    });

    test('固定攻击只有 4 档', () {
      // 档位 4（60）概率 3/103
      expect(
        percent(
          ProbabilityCalculator.reachProbability(
            tiers: const {},
            coefficients: flatAtkOnly,
            targetScore: 60.0,
          ),
        ),
        1.12, // (5/13)×(3/103)
      );
      // 档位 ≥3（≥50）概率 (39+3)/103
      expect(
        percent(
          ProbabilityCalculator.reachProbability(
            tiers: const {},
            coefficients: flatAtkOnly,
            targetScore: 50.0,
          ),
        ),
        15.68, // (5/13)×(42/103) = 15.6833%
      );
      // 目标 61 超过固定攻击的理论上限 60 → 0
      expect(
        percent(
          ProbabilityCalculator.reachProbability(
            tiers: const {},
            coefficients: flatAtkOnly,
            targetScore: 61.0,
          ),
        ),
        0.0,
      );
    });

    test('i=4：只剩 1 个槽位，从 9 个候选属性里抽', () {
      const tiers = {
        SubstatType.critRate: 1,
        SubstatType.critDmg: 1,
        SubstatType.atkPct: 1,
        SubstatType.hpPct: 1,
      };
      // 当前 6.3+12.6+6.4+6.4=31.7；候选 9 个属性中只有防御% 系数非 0（最高 14.7）
      ProbabilityOutcome? at(double target) =>
          ProbabilityCalculator.reachProbability(
            tiers: tiers,
            coefficients: fiveStats,
            targetScore: target,
          );

      // 需抽中防御% 且摇到档位 8（31.7+14.7=46.4）：(1/9)×(3/103)
      expect(percent(at(46.4)), 0.32);
      expect(at(46.4)!.probability, closeTo(3 / 927, 1e-12));

      // 需档位 ≥7（31.7+13.8=45.5）：(1/9)×(9/103)
      expect(percent(at(45.5)), 0.97);
      expect(at(45.5)!.probability, closeTo(9 / 927, 1e-12));

      // 需抽中防御%（任意档位，31.7+8.1=39.8）：1/9
      expect(percent(at(39.8)), 11.11);
      expect(at(39.8)!.probability, closeTo(1 / 9, 1e-12));

      // 目标 ≤ 当前分
      expect(percent(at(31.7)), 100.0);
      expect(percent(at(31.69)), 100.0);

      // 超出预期最高分 46.40
      expect(percent(at(46.41)), 0.0);
      expect(percent(at(47.0)), 0.0);
    });

    test('i=3：剩 2 个槽位，需两条同时摇满', () {
      const tiers = {
        SubstatType.critRate: 1,
        SubstatType.critDmg: 1,
        SubstatType.atkPct: 1,
      };
      // 当前 25.3；预期最高 = 25.3 + 生命% 11.6 + 防御% 14.7 = 51.6
      final outcome = ProbabilityCalculator.reachProbability(
        tiers: tiers,
        coefficients: fiveStats,
        targetScore: 51.6,
      )!;
      // 必须恰好抽中 {生命%, 防御%} 且两条都是档位 8：
      // (1/C(10,2)) × (3/103)^2 = (1/45) × 9/10609
      expect(outcome.probability, closeTo(9 / (45 * 10609), 1e-15));
      expect(outcome.percent, 0.0);
    });

    test('i=5：无剩余槽位，结果确定', () {
      const tiers = {
        SubstatType.critRate: 8,
        SubstatType.critDmg: 8,
        SubstatType.atkPct: 8,
        SubstatType.hpPct: 1,
        SubstatType.defPct: 1,
      };
      // 当前 10.5+21.0+11.6+6.4+8.1 = 57.6
      expect(
        percent(
          ProbabilityCalculator.reachProbability(
            tiers: tiers,
            coefficients: fiveStats,
            targetScore: 57.6,
          ),
        ),
        100.0,
      );
      expect(
        percent(
          ProbabilityCalculator.reachProbability(
            tiers: tiers,
            coefficients: fiveStats,
            targetScore: 57.61,
          ),
        ),
        0.0,
      );
    });

    test('全部系数为 0 时只有「目标 ≤ 当前分」才达成', () {
      final allZero = emptyCoefficients();
      expect(
        percent(
          ProbabilityCalculator.reachProbability(
            tiers: const {},
            coefficients: allZero,
            targetScore: 0.0,
          ),
        ),
        100.0,
      );
      expect(
        percent(
          ProbabilityCalculator.reachProbability(
            tiers: const {},
            coefficients: allZero,
            targetScore: 0.01,
          ),
        ),
        0.0,
      );
    });

    test('目标分带 2 位小数时按精确整数比较', () {
      // 攻击% = 0.75，i=0；理论最高 11.6×0.75 = 8.70
      final coefficients = normalizeCoefficients({SubstatType.atkPct: 0.75});
      final atMax = ProbabilityCalculator.reachProbability(
        tiers: const {},
        coefficients: coefficients,
        targetScore: 8.7,
      )!;
      // 抽中攻击% (5/13) 且档位 8 (3/103)
      expect(atMax.probability, closeTo(5 / 13 * 3 / 103, 1e-12));

      final justAbove = ProbabilityCalculator.reachProbability(
        tiers: const {},
        coefficients: coefficients,
        targetScore: 8.71,
      )!;
      expect(justAbove.probability, 0.0);
    });

    test('异常输入返回 null', () {
      expect(
        ProbabilityCalculator.reachProbability(
          tiers: const {
            SubstatType.critRate: 1,
            SubstatType.critDmg: 1,
            SubstatType.atkPct: 1,
            SubstatType.hpPct: 1,
            SubstatType.defPct: 1,
            SubstatType.energyRegen: 1,
          },
          coefficients: fiveStats,
          targetScore: 30.0,
        ),
        isNull,
        reason: '非 0 档位超过 5 条',
      );
      expect(
        ProbabilityCalculator.reachProbability(
          tiers: const {},
          coefficients: fiveStats,
          targetScore: double.nan,
        ),
        isNull,
      );
    });

    test('概率单调性：目标越高概率越低', () {
      var previous = 1.0;
      // 当前 6.9（暴击率2档），预期最高 6.9 + 暴伤21.0 + 防御%14.7 +
      // 攻击%11.6 + 生命%11.6 = 65.8；循环越过该上限以确保末尾概率归零。
      for (var target = 0.0; target <= 67.0; target += 1.0) {
        final outcome = ProbabilityCalculator.reachProbability(
          tiers: const {SubstatType.critRate: 2},
          coefficients: fiveStats,
          targetScore: target,
        )!;
        expect(
          outcome.probability,
          lessThanOrEqualTo(previous + 1e-12),
          reason: '目标 $target 的概率不应高于更低目标',
        );
        previous = outcome.probability;
      }
      expect(previous, 0.0);
    });
  });

  group('性能', () {
    test('13 个互不相同的系数 + 中间目标分，仍能在毫秒级完成', () {
      final coefficients = normalizeCoefficients({
        SubstatType.critRate: 1.0,
        SubstatType.critDmg: 0.9,
        SubstatType.atkPct: 0.8,
        SubstatType.hpPct: 0.7,
        SubstatType.defPct: 0.6,
        SubstatType.basicAtkBonus: 0.5,
        SubstatType.heavyAtkBonus: 0.4,
        SubstatType.skillBonus: 0.3,
        SubstatType.liberationBonus: 0.2,
        SubstatType.energyRegen: 0.1,
        SubstatType.flatAtk: 0.125,
        SubstatType.flatHp: 0.05,
        SubstatType.flatDef: 0.025,
      });
      final stopwatch = Stopwatch()..start();
      final outcome = ProbabilityCalculator.reachProbability(
        tiers: const {SubstatType.critRate: 3},
        coefficients: coefficients,
        targetScore: 16.0,
      );
      stopwatch.stop();
      expect(outcome, isNotNull);
      expect(outcome!.probability, greaterThan(0.0));
      expect(outcome.probability, lessThan(1.0));
      expect(outcome.approximate, isFalse, reason: '正常配置不应触发降精度');
      // 250ms 的阈值用于捕捉算法退化（暴力枚举需数分钟）。
      expect(stopwatch.elapsedMilliseconds, lessThan(250));
    });
  });
}
