import 'dart:io';

import '../data/repositories/background_image_service.dart';
import '../data/repositories/storage_service.dart';
import 'profile_controller.dart';
import 'settings_controller.dart';
import 'workspace_controller.dart';

/// 把三个控制器与存储服务串起来，处理需要跨控制器协调的操作。
class AppScope {
  AppScope({
    required this.storage,
    required this.settings,
    required this.profiles,
    required this.workspace,
    required this.background,
  });

  final StorageService storage;
  final SettingsController settings;
  final ProfileController profiles;
  final WorkspaceController workspace;

  /// 自定义背景图的导入与清理（复制到应用私有目录）。
  final BackgroundImageService background;

  /// 当前生效的存储根目录。
  Directory get root => storage.root;

  /// 切换存储根目录：迁移目录指针 → 记录偏好 → 重新加载两类数据。
  ///
  /// [path] 为空表示回到平台默认位置。旧目录的数据不会被移动或删除，
  /// 切回去即可继续使用。
  Future<void> changeStorageRoot(String? path) async {
    final directory = await StorageService.resolveRoot(path);
    await storage.changeRoot(directory);
    await settings.persistCustomStorageRoot(path);
    await profiles.reload();
    await workspace.resetForNewRoot();
  }
}
