import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/data/catalog/substat_type.dart';
import 'package:mingchao_echo_scorer/data/models/coefficients.dart';
import 'package:mingchao_echo_scorer/domain/expected_max_calculator.dart';

void main() {
  // 评分模型：分数 = 档位数值 × 系数（百分比属性按去掉 % 的数值计）。
  // fiveStats 各属性「系数 × 最高档位数值」增益：
  //   暴击伤害 1.0×21.0=21.0、防御% 1.0×14.7=14.7、攻击% 1.0×11.6=11.6、
  //   生命% 1.0×11.6=11.6、暴击率 1.0×10.5=10.5。
  final fiveStats = normalizeCoefficients({
    SubstatType.critRate: 1.0,
    SubstatType.critDmg: 1.0,
    SubstatType.atkPct: 1.0,
    SubstatType.hpPct: 1.0,
    SubstatType.defPct: 1.0,
  });

  final mixed = normalizeCoefficients({
    SubstatType.critRate: 1.0,
    SubstatType.critDmg: 1.0,
    SubstatType.atkPct: 0.75,
    SubstatType.energyRegen: 0.5,
  });

  group('预期最高分', () {
    test('i=0 时等于理论最高分，并给出最优的 5 条属性', () {
      final result = ExpectedMaxCalculator.calculate(
        tiers: const {},
        coefficients: fiveStats,
      )!;
      // 21.0 + 14.7 + 11.6 + 11.6 + 10.5，按增益降序排列。
      expect(result.value, 69.4);
      expect(result.filledCount, 0);
      expect(result.remainingSlots, 5);
      expect(result.bestRemaining, [
        SubstatType.critDmg,
        SubstatType.defPct,
        SubstatType.atkPct,
        SubstatType.hpPct,
        SubstatType.critRate,
      ]);
    });

    test('i=3 时补上剩余 2 条最优属性的满分', () {
      final result = ExpectedMaxCalculator.calculate(
        tiers: const {
          SubstatType.critRate: 1,
          SubstatType.critDmg: 1,
          SubstatType.atkPct: 1,
        },
        coefficients: fiveStats,
      )!;
      // 当前 6.3+12.6+6.4=25.3 + 防御% 14.7 + 生命% 11.6 = 51.6
      expect(result.value, 51.6);
      expect(result.remainingSlots, 2);
      expect(result.bestRemaining, [SubstatType.defPct, SubstatType.hpPct]);
    });

    test('i=4 时只补 1 条', () {
      final result = ExpectedMaxCalculator.calculate(
        tiers: const {
          SubstatType.critRate: 1,
          SubstatType.critDmg: 1,
          SubstatType.atkPct: 1,
          SubstatType.hpPct: 1,
        },
        coefficients: fiveStats,
      )!;
      // 当前 25.3+6.4=31.7 + 防御% 14.7 = 46.4
      expect(result.value, 46.4);
      expect(result.bestRemaining, [SubstatType.defPct]);
    });

    test('不放回：已选过的属性不会被再次选中', () {
      final result = ExpectedMaxCalculator.calculate(
        tiers: const {
          SubstatType.critRate: 1,
          SubstatType.critDmg: 1,
          SubstatType.atkPct: 1,
          SubstatType.hpPct: 1,
        },
        coefficients: fiveStats,
      )!;
      expect(result.bestRemaining, isNot(contains(SubstatType.critRate)));
      expect(result.bestRemaining, isNot(contains(SubstatType.critDmg)));
      expect(result.bestRemaining, isNot(contains(SubstatType.atkPct)));
      expect(result.bestRemaining, isNot(contains(SubstatType.hpPct)));
    });

    test('i=5 时预期最高分等于当前分数', () {
      const tiers = {
        SubstatType.critRate: 8,
        SubstatType.critDmg: 8,
        SubstatType.atkPct: 8,
        SubstatType.hpPct: 1,
        SubstatType.defPct: 1,
      };
      final result = ExpectedMaxCalculator.calculate(
        tiers: tiers,
        coefficients: fiveStats,
      )!;
      expect(result.remainingSlots, 0);
      expect(result.bestRemaining, isEmpty);
      // 10.5 + 21.0 + 11.6 + 6.4 + 8.1
      expect(result.value, 57.6);
    });

    test('剩余属性系数全为 0 时，预期最高分仍等于当前分数', () {
      final result = ExpectedMaxCalculator.calculate(
        tiers: const {SubstatType.critRate: 4},
        coefficients: mixed,
      )!;
      // 当前 暴击率4档 8.1 + 暴伤 21.0 + 攻击% 8.7 + 共鸣效率 6.2 + 一条 0 系数属性
      expect(result.value, 44.0);
      expect(result.bestRemaining, [
        SubstatType.critDmg,
        SubstatType.atkPct,
        SubstatType.energyRegen,
        SubstatType.hpPct,
      ]);
    });

    test('非 0 档位超过 5 条时返回 null', () {
      final result = ExpectedMaxCalculator.calculate(
        tiers: const {
          SubstatType.critRate: 1,
          SubstatType.critDmg: 1,
          SubstatType.atkPct: 1,
          SubstatType.hpPct: 1,
          SubstatType.defPct: 1,
          SubstatType.energyRegen: 1,
        },
        coefficients: fiveStats,
      );
      expect(result, isNull);
    });

    test('全 0 系数时预期最高分为 0', () {
      final result = ExpectedMaxCalculator.calculate(
        tiers: const {SubstatType.critRate: 8},
        coefficients: emptyCoefficients(),
      )!;
      expect(result.value, 0.0);
    });
  });
}
