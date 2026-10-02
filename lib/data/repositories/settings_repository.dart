import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式在磁盘上的取值，避免数据层依赖 Flutter 的 ThemeMode。
enum ThemeModeSetting {
  system('system'),
  light('light'),
  dark('dark');

  const ThemeModeSetting(this.key);

  final String key;

  static ThemeModeSetting fromKey(String? key) => values.firstWhere(
    (mode) => mode.key == key,
    orElse: () => ThemeModeSetting.system,
  );
}

/// 应用设置的读写（主题色、主题模式、存储位置、界面偏好）。
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _kCustomRoot = 'storage.customRoot';
  static const String _kSeedColor = 'theme.seedColor';
  static const String _kThemeMode = 'theme.mode';
  static const String _kBackgroundImage = 'theme.backgroundImage';
  static const String _kNavExpanded = 'ui.navExpanded';
  static const String _kLastOpenIds = 'workspace.lastOpenIds';
  static const String _kProfileLayout = 'library.profileLayout';
  static const String _kScoreLayout = 'library.scoreLayout';

  /// 默认主题种子色（深紫，与 Flutter 模板一致）。
  static const int defaultSeedColor = 0xFF6750A4;

  /// 用户自定义的存储根目录；null 表示使用平台默认位置。
  String? get customStorageRoot {
    final value = _prefs.getString(_kCustomRoot);
    return value == null || value.trim().isEmpty ? null : value;
  }

  Future<void> setCustomStorageRoot(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await _prefs.remove(_kCustomRoot);
    } else {
      await _prefs.setString(_kCustomRoot, path.trim());
    }
  }

  int get seedColor => _prefs.getInt(_kSeedColor) ?? defaultSeedColor;

  Future<void> setSeedColor(int value) => _prefs.setInt(_kSeedColor, value);

  ThemeModeSetting get themeMode =>
      ThemeModeSetting.fromKey(_prefs.getString(_kThemeMode));

  Future<void> setThemeMode(ThemeModeSetting mode) =>
      _prefs.setString(_kThemeMode, mode.key);

  /// 自定义背景图的本地路径；null 表示使用默认纯色背景。
  String? get backgroundImagePath {
    final value = _prefs.getString(_kBackgroundImage);
    return value == null || value.trim().isEmpty ? null : value;
  }

  Future<void> setBackgroundImagePath(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await _prefs.remove(_kBackgroundImage);
    } else {
      await _prefs.setString(_kBackgroundImage, path.trim());
    }
  }

  /// 左侧伸缩设置栏是否展开。
  bool get navExpanded => _prefs.getBool(_kNavExpanded) ?? true;

  Future<void> setNavExpanded(bool value) =>
      _prefs.setBool(_kNavExpanded, value);

  /// 上次退出时仍打开的评分文件 id，用于下次启动自动恢复。
  List<String> get lastOpenFileIds => _prefs.getStringList(_kLastOpenIds) ?? [];

  Future<void> setLastOpenFileIds(List<String> ids) =>
      _prefs.setStringList(_kLastOpenIds, ids);

  /// 角色系数配置列表的分组布局 token（组标题与条目 id 混排，见 LibraryLayout）。
  List<String> get profileLayoutTokens =>
      _prefs.getStringList(_kProfileLayout) ?? [];

  Future<void> setProfileLayoutTokens(List<String> tokens) =>
      _prefs.setStringList(_kProfileLayout, tokens);

  /// 评分文件列表的分组布局 token。
  List<String> get scoreLayoutTokens =>
      _prefs.getStringList(_kScoreLayout) ?? [];

  Future<void> setScoreLayoutTokens(List<String> tokens) =>
      _prefs.setStringList(_kScoreLayout, tokens);
}
