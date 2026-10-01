/// 评级档位，阈值基于「当前分 / 理论最高分」。
enum Rating {
  ace('ACE', 0.80),
  s('S', 0.70),
  a('A', 0.60),
  b('B', 0.50),
  c('C', 0.40),
  none('—', 0.0);

  const Rating(this.label, this.threshold);

  /// 显示文本；[Rating.none] 表示无评级。
  final String label;

  /// 达到该评级所需的最低比值。
  final double threshold;

  /// 浮点比较容差，避免 0.7、0.6 等阈值恰好命中时因二进制表示被降一级。
  static const double epsilon = 1e-9;

  bool get isRated => this != Rating.none;

  /// 由比值 [ratio] 映射到评级。恰好等于阈值时取较高的一档。
  static Rating fromRatio(double ratio) {
    if (ratio.isNaN) return Rating.none;
    for (final rating in values) {
      if (rating == Rating.none) continue;
      if (ratio + epsilon >= rating.threshold) return rating;
    }
    return Rating.none;
  }

  /// 由分数 [score] 与理论最高分 [max] 映射到评级。
  ///
  /// [max] 为 0（全部系数为 0）时无从比较，返回 [Rating.none]。
  static Rating fromScore(double score, double max) {
    if (max <= 0) return Rating.none;
    return fromRatio(score / max);
  }
}
