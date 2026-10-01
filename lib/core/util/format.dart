import '../../data/models/rating.dart';

/// 分数、评级等统一的显示格式。
class Format {
  const Format._();

  /// 分数固定 2 位小数，如 `244.11`。
  static String score(double value) => value.toStringAsFixed(2);

  /// `244.11分`。
  static String scoreWithUnit(double value) => '${score(value)}分';

  /// 评级文本：`A级`；无评级时为 `无评级`。
  static String rating(Rating rating) =>
      rating.isRated ? '${rating.label}级' : '无评级';

  /// 概率百分比，2 位小数，如 `1.15%`。
  static String percent(double probability) =>
      '${(probability * 100).toStringAsFixed(2)}%';

  /// 档位概率，2 位小数，如 `23.33%`。
  static String tierProbability(double probability) =>
      '${(probability * 100).toStringAsFixed(2)}%';

  /// `2026-10-01 15:30`。
  static String dateTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  /// 导出文件名里的时间戳，如 `20261001-153000`。
  static String timestamp(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}${two(local.month)}${two(local.day)}'
        '-${two(local.hour)}${two(local.minute)}${two(local.second)}';
  }
}
