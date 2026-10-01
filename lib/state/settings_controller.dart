import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repositories/settings_repository.dart';

/// 应用设置：主题色、主题模式、导航栏伸缩、自定义存储根目录。
class SettingsController extends ChangeNotifier {
  SettingsController(SharedPreferences preferences)
    : _repo = SettingsRepository(preferences);

  final SettingsRepository _repo;

  /// 供 [WorkspaceController] 记录「上次打开的文件」等界面偏好。
  SettingsRepository get repository => _repo;

  Color get seedColor => Color(_repo.seedColor);

  int get seedColorValue => _repo.seedColor;

  ThemeMode get themeMode => switch (_repo.themeMode) {
    ThemeModeSetting.light => ThemeMode.light,
    ThemeModeSetting.dark => ThemeMode.dark,
    ThemeModeSetting.system => ThemeMode.system,
  };

  bool get navExpanded => _repo.navExpanded;

  /// 自定义背景图的本地路径；null 表示使用默认纯色背景。
  String? get backgroundImagePath => _repo.backgroundImagePath;

  /// 用户在设置里指定的存储根目录；null 表示使用平台默认位置。
  String? get customStorageRoot => _repo.customStorageRoot;

  Future<void> setSeedColor(Color color) async {
    await _repo.setSeedColor(color.toARGB32());
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _repo.setThemeMode(switch (mode) {
      ThemeMode.light => ThemeModeSetting.light,
      ThemeMode.dark => ThemeModeSetting.dark,
      ThemeMode.system => ThemeModeSetting.system,
    });
    notifyListeners();
  }

  /// 记录（或清除，传 null）自定义背景图路径。
  ///
  /// 图片文件的复制/删除由 `BackgroundImageService` 负责，本方法只持久化路径，
  /// 与「存储位置」偏好一样属于纯界面偏好。
  Future<void> setBackgroundImagePath(String? path) async {
    await _repo.setBackgroundImagePath(path);
    notifyListeners();
  }

  Future<void> toggleNavExpanded() => setNavExpanded(!_repo.navExpanded);

  Future<void> setNavExpanded(bool value) async {
    await _repo.setNavExpanded(value);
    notifyListeners();
  }

  /// 只写入偏好，不切换实际目录；目录切换由 `AppScope.changeStorageRoot` 统一处理。
  Future<void> persistCustomStorageRoot(String? path) async {
    await _repo.setCustomStorageRoot(path);
    notifyListeners();
  }
}
