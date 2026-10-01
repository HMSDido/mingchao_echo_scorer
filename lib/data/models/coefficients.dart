import '../catalog/substat_type.dart';

/// 13 种副词条的系数表。
///
/// 约定：任何对外暴露的系数表都经过 [normalize]，即 13 个键全部存在，
/// 缺失项补 0，负值夹到 0。这样计算层无需再做空值判断。
typedef Coefficients = Map<SubstatType, double>;

/// 全 0 系数表（新建配置的默认值）。
Coefficients emptyCoefficients() => {
  for (final type in SubstatType.values) type: 0.0,
};

/// 补齐缺失键、夹掉负值，返回一份新的系数表。
Coefficients normalizeCoefficients(Coefficients? source) {
  final result = emptyCoefficients();
  if (source == null) return result;
  source.forEach((type, value) {
    if (value.isFinite && value > 0) result[type] = value;
  });
  return result;
}

/// 系数值允许的最大小数位数；超出部分在录入时被截断。
///
/// 概率计算依赖「系数 × 10^k 为整数」来做精确整数 DP，该常量决定了 k 的上界。
const int coefficientDecimalPlaces = 3;

/// 录入系数时的上限，防止把整数 DP 的取值范围撑爆。
const double coefficientMaxValue = 100.0;

/// 把系数四舍五入到 [coefficientDecimalPlaces] 位小数。
double quantizeCoefficient(double value) {
  if (!value.isFinite) return 0.0;
  final clamped = value.clamp(0.0, coefficientMaxValue).toDouble();
  const factor = 1000; // 10^coefficientDecimalPlaces
  return (clamped * factor).roundToDouble() / factor;
}

/// 系数表中出现过的不同取值（升序），用于概率 DP 的分组折叠。
List<double> distinctCoefficientValues(Coefficients coefficients) {
  final values = coefficients.values.toSet().toList()..sort();
  return values;
}
