import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/constants.dart';
import 'data/repositories/background_image_service.dart';
import 'data/repositories/profile_repository.dart';
import 'data/repositories/score_repository.dart';
import 'data/repositories/storage_service.dart';
import 'state/app_scope.dart';
import 'state/profile_controller.dart';
import 'state/settings_controller.dart';
import 'state/workspace_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final settings = SettingsController(preferences);
  final storage = StorageService(
    await StorageService.resolveRoot(settings.customStorageRoot),
  );

  final profiles = ProfileController(ProfileRepository(storage));
  final workspace = WorkspaceController(
    ScoreRepository(storage),
    storage,
    settings.repository,
  );
  final background = BackgroundImageService(
    await BackgroundImageService.resolveDefaultDirectory(),
  );
  final scope = AppScope(
    storage: storage,
    settings: settings,
    profiles: profiles,
    workspace: workspace,
    background: background,
  );

  // 窗口关闭拦截只在桌面端有意义，Android 上走系统返回键与页面级提示。
  final windowCloseGuard = Platform.isWindows;
  if (windowCloseGuard) await _configureWindow();

  runApp(
    MultiProvider(
      providers: [
        Provider<AppScope>.value(value: scope),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<ProfileController>.value(value: profiles),
        ChangeNotifierProvider<WorkspaceController>.value(value: workspace),
      ],
      child: EchoScorerApp(windowCloseGuard: windowCloseGuard),
    ),
  );

  // 磁盘扫描放到首帧之后：主区域在 `loading` 期间本来就有转圈占位，
  // 先出壳再补数据，感知启动更快。目录结构由 bootstrap 内的 ensureStructure 建立。
  unawaited(Future.wait([profiles.reload(), workspace.bootstrap()]));
}

Future<void> _configureWindow() async {
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1180, 780),
    minimumSize: Size(420, 520),
    center: true,
    title: AppConstants.appName,
    windowButtonVisibility: true,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });
}
