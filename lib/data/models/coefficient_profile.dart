import 'coefficients.dart';
import 'id_generator.dart';
import 'json_format.dart';

/// 角色系数配置：一份可复用的 13 词条权重文件。
class CoefficientProfile {
  const CoefficientProfile({
    required this.id,
    required this.name,
    required this.coefficients,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 新建一份全 0 系数的配置。
  factory CoefficientProfile.create(String name, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return CoefficientProfile(
      id: newId(),
      name: name,
      coefficients: emptyCoefficients(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  final String id;
  final String name;

  /// 恒为 13 键齐全的规范化系数表。
  final Coefficients coefficients;
  final DateTime createdAt;
  final DateTime updatedAt;

  CoefficientProfile copyWith({
    String? name,
    Coefficients? coefficients,
    DateTime? updatedAt,
  }) => CoefficientProfile(
    id: id,
    name: name ?? this.name,
    coefficients: coefficients == null
        ? this.coefficients
        : normalizeCoefficients(coefficients),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  bool get isAllZero => coefficients.values.every((value) => value == 0);

  Map<String, dynamic> toJson() => {
    'format': jsonFormatVersion,
    'id': id,
    'name': name,
    'coefficients': coefficientsToJson(coefficients),
    'createdAt': isoDate(createdAt),
    'updatedAt': isoDate(updatedAt),
  };

  /// 解析磁盘 JSON；结构不合法时抛 [FormatException]。
  static CoefficientProfile fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('角色系数配置缺少有效的 id');
    }
    return CoefficientProfile(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name.trim() : '未命名配置',
      coefficients: coefficientsFromJson(json['coefficients']),
      createdAt: parseDate(json['createdAt'], now),
      updatedAt: parseDate(json['updatedAt'], now),
    );
  }
}
