/// 文件名/文件夹名清理工具。
///
/// 评分文件以「用户自命名文件夹」形式落盘，因此文件夹名必须同时满足
/// Windows 与 Android 的文件系统限制。
class FileNames {
  const FileNames._();

  /// Windows 保留设备名，不能用作文件名。
  static const Set<String> _reserved = {
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  static const int _maxLength = 60;

  /// 非法字符：`\ / : * ? " < > |` 与控制字符。
  static final RegExp _illegal = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

  /// 把任意用户输入清理成安全的单层文件夹名。
  ///
  /// 结果为空或命中保留名时返回 [fallback]。绝不返回含路径分隔符的字符串，
  /// 因此不会造成目录穿越。
  static String sanitize(String input, {required String fallback}) {
    var name = input.replaceAll(_illegal, '_').trim();
    // Windows 不允许名字以点或空格结尾。
    name = name.replaceAll(RegExp(r'[. ]+$'), '');
    if (name.length > _maxLength) {
      name = name.substring(0, _maxLength).replaceAll(RegExp(r'[. ]+$'), '');
    }
    if (name.isEmpty) return fallback;
    if (_reserved.contains(name.toUpperCase())) return fallback;
    return name;
  }

  /// 名字是否已经是安全的文件夹名。
  static bool isSafe(String name) =>
      sanitize(name, fallback: '') == name && name.isNotEmpty;

  /// 在 [existing] 中为 [desired] 找一个不冲突的名字：`名字 (2)`、`名字 (3)`…
  static String deduplicate(String desired, Iterable<String> existing) {
    final taken = existing.toSet();
    if (!taken.contains(desired)) return desired;
    for (var suffix = 2; suffix < 10000; suffix++) {
      final candidate = '$desired ($suffix)';
      if (!taken.contains(candidate)) return candidate;
    }
    return '$desired (${DateTime.now().millisecondsSinceEpoch})';
  }
}
