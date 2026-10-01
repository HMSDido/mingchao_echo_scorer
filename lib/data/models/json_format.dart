import '../catalog/substat_type.dart';
import 'coefficients.dart';

/// 磁盘 JSON 的格式版本，用于将来的数据迁移。
const int jsonFormatVersion = 1;

/// 读取整数版本号；缺失或非法时视为 1。
int readFormatVersion(Map<String, dynamic> json) {
  final raw = json['format'];
  return raw is int && raw > 0 ? raw : 1;
}

/// 系数表 → JSON（只写非 0 项，文件更紧凑，缺项读取时按 0 补齐）。
Map<String, dynamic> coefficientsToJson(Coefficients coefficients) => {
  for (final entry in coefficients.entries)
    if (entry.value != 0) entry.key.jsonKey: entry.value,
};

/// JSON → 系数表，未知键忽略、缺失键补 0、负值夹到 0。
Coefficients coefficientsFromJson(Object? raw) {
  final result = emptyCoefficients();
  if (raw is! Map) return result;
  raw.forEach((key, value) {
    if (key is! String) return;
    final type = SubstatType.fromJsonKey(key);
    if (type == null) return;
    final number = _asDouble(value);
    if (number == null || number <= 0) return;
    result[type] = quantizeCoefficient(number);
  });
  return result;
}

double? _asDouble(Object? value) => switch (value) {
  num n => n.toDouble(),
  String s => double.tryParse(s),
  _ => null,
};

/// 档位表 → JSON（只写非 0 档位）。
Map<String, dynamic> tiersToJson(Map<SubstatType, int> tiers) => {
  for (final entry in tiers.entries)
    if (entry.value > 0) entry.key.jsonKey: entry.value,
};

/// JSON → 档位表；超出该属性档位数上限的值夹到上限，非法值丢弃。
Map<SubstatType, int> tiersFromJson(Object? raw) {
  final result = <SubstatType, int>{};
  if (raw is! Map) return result;
  raw.forEach((key, value) {
    if (key is! String) return;
    final type = SubstatType.fromJsonKey(key);
    if (type == null) return;
    final tier = _asDouble(value)?.round();
    if (tier == null || tier <= 0) return;
    result[type] = tier > type.maxTier ? type.maxTier : tier;
  });
  return result;
}

String isoDate(DateTime value) => value.toUtc().toIso8601String();

DateTime parseDate(Object? raw, DateTime fallback) {
  if (raw is! String) return fallback;
  return DateTime.tryParse(raw) ?? fallback;
}
