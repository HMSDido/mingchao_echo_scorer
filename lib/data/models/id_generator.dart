import 'dart:math';

final Random _random = Random();

/// 生成一个进程内唯一、跨进程极低碰撞概率的短 id。
///
/// 不引入 uuid 依赖：id 只用于文件名与内部引用，不需要 RFC 4122 语义。
String newId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = _random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
  return '$time-$salt';
}
