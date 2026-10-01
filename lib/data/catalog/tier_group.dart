/// 副词条档位的概率分组。
///
/// 概率一律用「整数分子 / 组内公分母」表示，避免 23.3333% 之类的十进制
/// 截断误差进入后续计算。
enum TierGroup {
  /// 暴击率、暴击伤害共用：8 档，7/30、7/30、7/30、2/25、2/25、2/25、3/100、3/100。
  crit(numerators: [70, 70, 70, 24, 24, 24, 9, 9], denominator: 300),

  /// 百分比类 9 属性共用（含固定生命）：8 档。
  percentLike(numerators: [7, 8, 21, 25, 18, 15, 6, 3], denominator: 103),

  /// 固定攻击：4 档。
  flatAtk(numerators: [7, 54, 39, 3], denominator: 103),

  /// 固定防御：4 档。
  flatDef(numerators: [15, 46, 33, 9], denominator: 103);

  const TierGroup({required this.numerators, required this.denominator});

  /// 各档位概率分子，下标 0 对应档位 1。
  final List<int> numerators;

  /// 组内公分母。
  final int denominator;

  /// 该组的档位总数（不含档位 0）。
  int get tierCount => numerators.length;

  /// 档位 [tier]（1 起）的概率，返回值域 [0, 1]。
  ///
  /// 档位 0 表示「尚未开出此副词条」，不计入概率，故此处非法。
  double probabilityOf(int tier) {
    assert(tier >= 1 && tier <= tierCount, 'tier $tier 超出 $name 的范围');
    return numerators[tier - 1] / denominator;
  }

  /// 全组概率之和，恒为 1。供自检测试使用。
  double get probabilitySum =>
      numerators.fold(0, (sum, n) => sum + n) / denominator;

  /// 概率分子的整数和，恒等于 [denominator]。供自检测试使用。
  int get numeratorSum => numerators.fold(0, (sum, n) => sum + n);
}
