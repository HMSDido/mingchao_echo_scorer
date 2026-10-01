import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/data/catalog/substat_type.dart';
import 'package:mingchao_echo_scorer/data/models/coefficients.dart';
import 'package:mingchao_echo_scorer/data/models/echo_entry.dart';
import 'package:mingchao_echo_scorer/data/models/rating.dart';
import 'package:mingchao_echo_scorer/domain/score_calculator.dart';

EchoEntry echo(int slot, Map<SubstatType, int> tiers) =>
    EchoEntry(slot: slot, name: EchoEntry.defaultNameOf(slot), tiers: tiers);

void main() {
  // 评分 = Σ(档位数值 × 系数)。各属性满档数值：
  // 暴击率 10.5、暴伤 21.0、攻击% 11.6、生命% 11.6、防御% 14.7、共鸣效率 12.4、
  // 固定攻击 60、固定防御 70。

  // 暴击率=1，其余 0：理论最高分 = 1.0 × 10.5 = 10.50
  final critOnly = normalizeCoefficients({SubstatType.critRate: 1.0});

  // 暴击率=1, 暴伤=1, 攻击%=0.75, 共鸣效率=0.5
  // 理论最高 = 10.5 + 21.0 + 8.7 + 6.2 + 0 = 46.40
  final mixed = normalizeCoefficients({
    SubstatType.critRate: 1.0,
    SubstatType.critDmg: 1.0,
    SubstatType.atkPct: 0.75,
    SubstatType.energyRegen: 0.5,
  });

  // 5 条主属性各 1.0：理论最高 = 10.5 + 21.0 + 11.6 + 11.6 + 14.7 = 69.40
  final fiveStats = normalizeCoefficients({
    SubstatType.critRate: 1.0,
    SubstatType.critDmg: 1.0,
    SubstatType.atkPct: 1.0,
    SubstatType.hpPct: 1.0,
    SubstatType.defPct: 1.0,
  });

  group('理论最高分', () {
    test('取 系数×最高档位数值 的前 5 项之和', () {
      expect(ScoreCalculator.echoMaxRaw(critOnly), closeTo(10.5, 1e-9));
      expect(ScoreCalculator.echoMaxRaw(mixed), closeTo(46.4, 1e-9));
      expect(ScoreCalculator.echoMaxRaw(fiveStats), closeTo(69.4, 1e-9));
    });

    test('固定攻击/固定防御按满档数值计入理论最高分', () {
      final flat = normalizeCoefficients({
        SubstatType.flatAtk: 1.0,
        SubstatType.flatDef: 1.0,
      });
      // 固定攻击满档 +60、固定防御满档 +70 → 130.00
      expect(ScoreCalculator.echoMaxRaw(flat), closeTo(130.0, 1e-9));
    });

    test('全 0 系数时理论最高分为 0', () {
      expect(ScoreCalculator.echoMaxRaw(emptyCoefficients()), 0.0);
    });

    test('总理论最高分 = 5 × 单件', () {
      final file = ScoreCalculator.scoreFile(
        List.generate(EchoEntry.slotCount, EchoEntry.create),
        mixed,
      );
      expect(file.totalMaxScore, closeTo(232.0, 1e-9));
    });
  });

  group('单件声骸评分', () {
    test('暴击率档位 3（7.5%）→ 7.50 分，比值 71.4% → S 级', () {
      final result = ScoreCalculator.scoreEcho(
        echo(0, {SubstatType.critRate: 3}),
        critOnly,
      );
      expect(result.raw, closeTo(7.5, 1e-12));
      expect(result.score, 7.5);
      expect(result.maxScore, 10.5);
      expect(result.ratio, closeTo(5 / 7, 1e-12));
      expect(result.rating, Rating.s);
      expect(result.filledCount, 1);
      expect(result.isOverFilled, isFalse);
    });

    test('多条词条按 档位数值×系数 加权求和', () {
      final result = ScoreCalculator.scoreEcho(
        echo(0, {
          SubstatType.critRate: 8,
          SubstatType.critDmg: 8,
          SubstatType.atkPct: 8,
          SubstatType.energyRegen: 8,
        }),
        mixed,
      );
      // 10.5 + 21.0 + 11.6×0.75(=8.7) + 12.4×0.5(=6.2) = 46.40，恰为理论最高 → ACE
      expect(result.score, closeTo(46.4, 1e-9));
      expect(result.rating, Rating.ace);
    });

    test('系数为 0 的词条不计分', () {
      final result = ScoreCalculator.scoreEcho(
        echo(0, {SubstatType.critRate: 5, SubstatType.flatDef: 4}),
        critOnly,
      );
      // 暴击率档位 5 = 8.7% → 8.7 分；固定防御系数 0 不计。
      expect(result.score, closeTo(8.7, 1e-9));
    });

    test('空声骸得 0 分、无评级', () {
      final result = ScoreCalculator.scoreEcho(EchoEntry.create(0), mixed);
      expect(result.score, 0.0);
      expect(result.filledCount, 0);
      expect(result.rating, Rating.none);
    });

    test('全精度累加后统一取 2 位小数，而非逐项取整', () {
      final coefficients = normalizeCoefficients({
        SubstatType.atkPct: 0.115,
        SubstatType.hpPct: 0.115,
      });
      final result = ScoreCalculator.scoreEcho(
        echo(0, {SubstatType.atkPct: 8, SubstatType.hpPct: 8}),
        coefficients,
      );
      // 每项 11.6 × 0.115 = 1.334；逐项取整会得到 1.33 + 1.33 = 2.66，
      // 全精度累加 2.668 → 2.67 才是正确答案。
      expect(result.raw, closeTo(2.668, 1e-9));
      expect(result.score, 2.67);
    });

    test('非 0 档位超过 5 条时不输出结果', () {
      final result = ScoreCalculator.scoreEcho(
        echo(0, {
          SubstatType.critRate: 1,
          SubstatType.critDmg: 1,
          SubstatType.atkPct: 1,
          SubstatType.hpPct: 1,
          SubstatType.defPct: 1,
          SubstatType.energyRegen: 1,
        }),
        fiveStats,
      );
      expect(result.isOverFilled, isTrue);
      expect(result.filledCount, 6);
      expect(result.rating, Rating.none);
    });
  });

  group('总分与总评级', () {
    test('总分 = 5 件显示分之和', () {
      final echoes = [
        echo(0, {SubstatType.critRate: 8, SubstatType.critDmg: 8}), // 31.5
        echo(1, {SubstatType.atkPct: 8}), // 11.6
        echo(2, {SubstatType.hpPct: 4}), // 8.6
        echo(3, {}), // 0
        echo(4, {SubstatType.defPct: 2}), // 9.0
      ];
      final file = ScoreCalculator.scoreFile(echoes, fiveStats);
      // 31.5 + 11.6 + 8.6 + 0 + 9.0 = 60.7
      expect(file.totalScore, closeTo(60.7, 1e-9));
      expect(file.totalMaxScore, closeTo(347.0, 1e-9));
      expect(file.totalRating, Rating.none); // 60.7 / 347 ≈ 17.5%
    });

    test('总分比值约 66.6% → A 级', () {
      final echoes = List.generate(
        EchoEntry.slotCount,
        (slot) => echo(slot, {
          SubstatType.critRate: 8,
          SubstatType.critDmg: 8,
          SubstatType.defPct: 8,
        }),
      );
      final file = ScoreCalculator.scoreFile(echoes, fiveStats);
      // 每件 10.5 + 21.0 + 14.7 = 46.2，总分 231.0；理论最高 5 × 69.4 = 347.0
      // → 231/347 ≈ 66.6%，落在 A 级区间（60%–70%）
      expect(file.echoes.first.score, closeTo(46.2, 1e-9));
      expect(file.totalScore, closeTo(231.0, 1e-9));
      expect(file.ratio, closeTo(231.0 / 347.0, 1e-12));
      expect(file.totalRating, Rating.a);
    });

    test('空文件的总分为 0、无评级', () {
      final file = ScoreCalculator.scoreFile(
        List.generate(EchoEntry.slotCount, EchoEntry.create),
        fiveStats,
      );
      expect(file.totalScore, 0.0);
      expect(file.totalRating, Rating.none);
    });
  });

  group('副词条合计与暴击阈值', () {
    final twoCritEchoes = [
      echo(0, {SubstatType.critRate: 8}), // 10.5
      echo(1, {SubstatType.critRate: 8}), // 10.5
      echo(2, {}),
      echo(3, {}),
      echo(4, {}),
    ];

    test('合计为 5 件声骸各属性档位数值之和', () {
      final echoes = [
        echo(0, {SubstatType.critRate: 3, SubstatType.flatAtk: 2}), // 7.5 / 40
        echo(1, {SubstatType.critRate: 5, SubstatType.flatAtk: 2}), // 8.7 / 40
        echo(2, {}),
        echo(3, {}),
        echo(4, {}),
      ];
      final totals = ScoreCalculator.substatTotals(echoes);
      expect(totals[SubstatType.critRate], closeTo(16.2, 1e-9));
      expect(totals[SubstatType.flatAtk], 80.0);
      expect(totals[SubstatType.critDmg], 0.0);
    });

    test('超填的声骸不计入合计', () {
      final echoes = [
        echo(0, {
          SubstatType.critRate: 1,
          SubstatType.critDmg: 1,
          SubstatType.atkPct: 1,
          SubstatType.hpPct: 1,
          SubstatType.defPct: 1,
          SubstatType.energyRegen: 1,
        }),
        echo(1, {SubstatType.critRate: 2}), // 6.9
        echo(2, {}),
        echo(3, {}),
        echo(4, {}),
      ];
      final totals = ScoreCalculator.substatTotals(echoes);
      expect(totals[SubstatType.critRate], closeTo(6.9, 1e-9));
    });

    test('未设阈值时合计不影响总分', () {
      final file = ScoreCalculator.scoreFile(twoCritEchoes, critOnly);
      expect(file.critSum, closeTo(21.0, 1e-9));
      expect(file.critExcess, 0.0);
      expect(file.hasCritOverflow, isFalse);
      expect(file.totalScore, closeTo(21.0, 1e-9));
      expect(file.totalRating, Rating.c); // 21 / 52.5 = 40% 恰为 C 级门槛
    });

    test('合计未超过阈值时不截断', () {
      final file = ScoreCalculator.scoreFile(
        twoCritEchoes,
        critOnly,
        critThreshold: 25.0,
      );
      expect(file.critExcess, 0.0);
      expect(file.hasCritOverflow, isFalse);
      expect(file.totalScore, closeTo(21.0, 1e-9));
    });

    test('超出阈值的部分按暴击率系数从总分中扣除', () {
      final file = ScoreCalculator.scoreFile(
        twoCritEchoes,
        critOnly,
        critThreshold: 15.0,
      );
      // 合计 21.0、超出 6.0、暴击率系数 1.0 → 21.0 − 6.0 = 15.0
      expect(file.critExcess, closeTo(6.0, 1e-9));
      expect(file.hasCritOverflow, isTrue);
      expect(file.totalScore, closeTo(15.0, 1e-9));
      // 评级跟随截断后的总分：15 / 52.5 ≈ 28.6% → 无评级
      expect(file.totalRating, Rating.none);
    });

    test('扣除量随暴击率系数缩放', () {
      final halfCrit = normalizeCoefficients({SubstatType.critRate: 0.5});
      final file = ScoreCalculator.scoreFile(
        twoCritEchoes,
        halfCrit,
        critThreshold: 15.0,
      );
      // 每件 5.25、总分 10.5；超出 6.0 × 0.5 = 3.0 → 7.5
      expect(file.totalScore, closeTo(7.5, 1e-9));
    });
  });

  group('系数规范化', () {
    test('缺失键补 0、负值与 NaN 夹到 0', () {
      final normalized = normalizeCoefficients({
        SubstatType.critRate: 1.0,
        SubstatType.critDmg: -2.0,
        SubstatType.atkPct: double.nan,
      });
      expect(normalized, hasLength(13));
      expect(normalized[SubstatType.critRate], 1.0);
      expect(normalized[SubstatType.critDmg], 0.0);
      expect(normalized[SubstatType.atkPct], 0.0);
      expect(normalized[SubstatType.flatDef], 0.0);
    });

    test('录入系数被量化到 3 位小数并夹到上限', () {
      expect(quantizeCoefficient(0.75555), 0.756);
      expect(quantizeCoefficient(-1), 0.0);
      expect(quantizeCoefficient(1e9), coefficientMaxValue);
      expect(quantizeCoefficient(double.infinity), 0.0);
    });
  });
}
