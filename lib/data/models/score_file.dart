import '../catalog/substat_type.dart';
import 'coefficients.dart';
import 'coefficient_profile.dart';
import 'echo_entry.dart';
import 'id_generator.dart';
import 'json_format.dart';

/// 一个角色声骸评分文件：包含 5 件声骸的录入数据 + 所选角色系数的**快照**。
///
/// 快照语义：选定角色后系数被复制进本文件，此后修改原配置不会影响已存文件，
/// 需要时由用户显式「重新套用配置」。
class ScoreFile {
  const ScoreFile({
    required this.id,
    required this.name,
    required this.profileId,
    required this.profileName,
    required this.coefficients,
    required this.echoes,
    required this.updatedAt,
    this.critThreshold,
  });

  /// 新建评分文件并套用 [profile] 的系数快照。
  factory ScoreFile.fromProfile({
    required String name,
    required CoefficientProfile profile,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    return ScoreFile(
      id: newId(),
      name: name,
      profileId: profile.id,
      profileName: profile.name,
      coefficients: normalizeCoefficients(profile.coefficients),
      echoes: List.generate(EchoEntry.slotCount, EchoEntry.create),
      updatedAt: timestamp,
    );
  }

  /// 尚未选择角色的空文件；此时 [coefficients] 全 0，主界面应提示「选择角色」。
  factory ScoreFile.empty({required String name, DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return ScoreFile(
      id: newId(),
      name: name,
      profileId: '',
      profileName: '',
      coefficients: emptyCoefficients(),
      echoes: List.generate(EchoEntry.slotCount, EchoEntry.create),
      updatedAt: timestamp,
    );
  }

  final String id;

  /// 用户命名，同时作为磁盘上的文件夹名。
  final String name;

  /// 来源配置的 id；空串表示尚未选择角色。
  final String profileId;
  final String profileName;

  /// 恒为 13 键齐全的规范化系数表（快照）。
  final Coefficients coefficients;

  /// 恒为 [EchoEntry.slotCount] 个，按 slot 升序。
  final List<EchoEntry> echoes;

  final DateTime updatedAt;

  /// 暴击率阈值（百分比数值，如 `25.0` 表示 25.0%），null 表示不设阈值。
  ///
  /// 设了阈值后，5 件声骸的暴击率合计超出该值的部分不再计入总分，
  /// 具体口径见 `ScoreCalculator.scoreFile`。
  final double? critThreshold;

  bool get hasProfile => profileId.isNotEmpty;

  EchoEntry echoAt(int slot) => echoes[slot];

  ScoreFile copyWith({
    String? name,
    String? profileId,
    String? profileName,
    Coefficients? coefficients,
    List<EchoEntry>? echoes,
    DateTime? updatedAt,
    double? critThreshold,
    bool clearCritThreshold = false,
  }) => ScoreFile(
    id: id,
    name: name ?? this.name,
    profileId: profileId ?? this.profileId,
    profileName: profileName ?? this.profileName,
    coefficients: coefficients == null
        ? this.coefficients
        : normalizeCoefficients(coefficients),
    echoes: echoes ?? this.echoes,
    updatedAt: updatedAt ?? this.updatedAt,
    critThreshold: clearCritThreshold
        ? null
        : (critThreshold ?? this.critThreshold),
  );

  /// 替换指定槽位的声骸数据（详情页「保存本声骸」走这里）。
  ScoreFile withEcho(EchoEntry echo) {
    final next = List<EchoEntry>.from(echoes);
    next[echo.slot] = echo;
    return copyWith(echoes: next);
  }

  /// 重新套用配置的系数快照。
  ScoreFile applyingProfile(CoefficientProfile profile) => copyWith(
    profileId: profile.id,
    profileName: profile.name,
    coefficients: normalizeCoefficients(profile.coefficients),
  );

  ScoreFile touched(DateTime timestamp) => copyWith(updatedAt: timestamp);

  /// 录入内容是否与 [other] 一致（忽略 [updatedAt]）。
  ///
  /// 脏检查的依据：与最近一次落盘的内容比较，只有真正改过才提示保存。
  bool sameContentAs(ScoreFile other) {
    if (id != other.id) return false;
    if (name != other.name) return false;
    if (profileId != other.profileId || profileName != other.profileName) {
      return false;
    }
    for (final type in SubstatType.values) {
      if (coefficients[type] != other.coefficients[type]) return false;
    }
    if (echoes.length != other.echoes.length) return false;
    for (var i = 0; i < echoes.length; i++) {
      if (!echoes[i].sameContentAs(other.echoes[i])) return false;
    }
    return _sameOptionalDouble(critThreshold, other.critThreshold);
  }

  Map<String, dynamic> toJson() => {
    'format': jsonFormatVersion,
    'id': id,
    'name': name,
    'profile': {'id': profileId, 'name': profileName},
    'coefficients': coefficientsToJson(coefficients),
    'echoes': echoes.map((echo) => echo.toJson()).toList(),
    'updatedAt': isoDate(updatedAt),
    if (critThreshold != null) 'critThreshold': critThreshold,
  };

  static ScoreFile fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('评分文件缺少有效的 id');
    }
    final name = json['name'];
    final profile = json['profile'];

    final rawEchoes = json['echoes'];
    final parsed = <EchoEntry>[];
    if (rawEchoes is List) {
      for (var i = 0; i < rawEchoes.length; i++) {
        final item = rawEchoes[i];
        if (item is Map<String, dynamic>) {
          parsed.add(EchoEntry.fromJson(item, i));
        }
      }
    }
    // 磁盘数据可能被截断或槽位重复：按 slot 归位，缺失槽补默认值。
    final echoes = List<EchoEntry>.generate(
      EchoEntry.slotCount,
      EchoEntry.create,
      growable: false,
    );
    for (final echo in parsed) {
      if (echo.slot >= 0 && echo.slot < EchoEntry.slotCount) {
        echoes[echo.slot] = echo;
      }
    }

    return ScoreFile(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name.trim() : '未命名文件',
      profileId: profile is Map && profile['id'] is String
          ? profile['id'] as String
          : '',
      profileName: profile is Map && profile['name'] is String
          ? profile['name'] as String
          : '',
      coefficients: coefficientsFromJson(json['coefficients']),
      echoes: echoes,
      updatedAt: parseDate(json['updatedAt'], now),
      critThreshold: _thresholdFromJson(json['critThreshold']),
    );
  }
}

/// 阈值是选填项：缺失、非数字或负数一律视为「不设阈值」。
double? _thresholdFromJson(Object? raw) =>
    raw is num && raw >= 0 ? raw.toDouble() : null;

/// NaN 与自身不相等，直接 `==` 会让含 NaN 的阈值永远判定为「已改动」。
bool _sameOptionalDouble(double? a, double? b) {
  if (a == null || b == null) return a == null && b == null;
  if (a.isNaN && b.isNaN) return true;
  return (a - b).abs() < 1e-9;
}
