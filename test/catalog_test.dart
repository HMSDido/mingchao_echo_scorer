import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/data/catalog/substat_type.dart';
import 'package:mingchao_echo_scorer/data/catalog/tier_group.dart';

void main() {
  group('档位概率表', () {
    test('每组概率分子之和恰等于公分母', () {
      for (final group in TierGroup.values) {
        expect(
          group.numeratorSum,
          group.denominator,
          reason: '${group.name} 的概率分子之和应为 ${group.denominator}',
        );
        expect(group.probabilitySum, closeTo(1.0, 1e-12));
      }
    });

    test('暴击组用 300 公分母表达 7/30、2/25、3/100', () {
      expect(TierGroup.crit.tierCount, 8);
      expect(TierGroup.crit.probabilityOf(1), closeTo(7 / 30, 1e-12));
      expect(TierGroup.crit.probabilityOf(4), closeTo(2 / 25, 1e-12));
      expect(TierGroup.crit.probabilityOf(8), closeTo(3 / 100, 1e-12));
    });

    test('档位数：暴击组与百分比组 8 档，固定攻击/固定防御 4 档', () {
      expect(TierGroup.percentLike.tierCount, 8);
      expect(TierGroup.flatAtk.tierCount, 4);
      expect(TierGroup.flatDef.tierCount, 4);
    });
  });

  group('13 种副词条', () {
    test('数量与顺序符合需求', () {
      expect(SubstatType.values, hasLength(13));
      expect(SubstatType.values.map((type) => type.label).toList(), [
        '暴击率',
        '暴击伤害',
        '攻击%',
        '生命%',
        '防御%',
        '普攻伤害加成',
        '重击伤害加成',
        '共鸣技能伤害加成',
        '共鸣解放伤害加成',
        '共鸣效率',
        '固定攻击',
        '固定生命',
        '固定防御',
      ]);
    });

    test('每个属性的档位数值个数等于其组档位数', () {
      for (final type in SubstatType.values) {
        expect(
          type.tierValues,
          hasLength(type.group.tierCount),
          reason: '${type.label} 的档位数值个数不匹配',
        );
      }
    });

    test('分组归属：固定生命走 8 档百分比组，固定攻击/固定防御各 4 档', () {
      expect(SubstatType.critRate.group, TierGroup.crit);
      expect(SubstatType.critDmg.group, TierGroup.crit);
      expect(SubstatType.flatHp.group, TierGroup.percentLike);
      expect(SubstatType.flatAtk.group, TierGroup.flatAtk);
      expect(SubstatType.flatDef.group, TierGroup.flatDef);
      const percentMembers = {
        SubstatType.atkPct,
        SubstatType.hpPct,
        SubstatType.defPct,
        SubstatType.basicAtkBonus,
        SubstatType.heavyAtkBonus,
        SubstatType.skillBonus,
        SubstatType.liberationBonus,
        SubstatType.energyRegen,
        SubstatType.flatHp,
      };
      expect(
        percentMembers.where((t) => t.group == TierGroup.percentLike),
        hasLength(9),
      );
    });

    test('关键档位数值抽查', () {
      expect(SubstatType.critRate.displayValueOf(1), '6.3%');
      expect(SubstatType.critRate.displayValueOf(8), '10.5%');
      expect(SubstatType.critDmg.displayValueOf(3), '15.0%');
      expect(SubstatType.defPct.displayValueOf(2), '9.0%');
      expect(SubstatType.energyRegen.displayValueOf(5), '10.0%');
      expect(SubstatType.flatAtk.displayValueOf(2), '40');
      expect(SubstatType.flatHp.displayValueOf(4), '430');
      expect(SubstatType.flatDef.displayValueOf(4), '70');
    });

    test('JSON 键名唯一且可反查', () {
      final keys = SubstatType.values.map((t) => t.jsonKey).toSet();
      expect(keys, hasLength(13));
      for (final type in SubstatType.values) {
        expect(SubstatType.fromJsonKey(type.jsonKey), type);
      }
      expect(SubstatType.fromJsonKey('不存在的键'), isNull);
    });
  });
}
