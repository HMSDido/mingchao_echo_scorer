import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 自定义背景图的导入与清理。
///
/// 用户选中的图片一律先复制进应用私有目录（[resolveDefaultDirectory]）再引用，
/// 不直接持有外部原始路径 —— 外部 URI 在 Android 上可能因权限回收或重启而失效。
/// 全程只读写本地文件，不涉及任何网络请求。
class BackgroundImageService {
  BackgroundImageService(this.directory);

  /// 背景图的存放目录（应用私有）。
  final Directory directory;

  /// 允许导入的图片扩展名（小写、不含点）。
  static const Set<String> allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  /// 解析默认存放目录：`<应用私有目录>/background`。
  static Future<Directory> resolveDefaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'background'));
  }

  /// [path] 是否为允许的图片类型。
  static bool isAllowedPath(String? path) {
    if (path == null) return false;
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return allowedExtensions.contains(ext);
  }

  /// 把 [source] 复制进私有目录，返回复制后的绝对路径。
  ///
  /// 每次导入都用带时间戳的唯一文件名，避免 Flutter 的图片缓存按路径命中旧图；
  /// 复制成功后删除 [previousPath] 指向的旧背景文件（若有），不残留占用空间。
  Future<String> import(File source, {String? previousPath}) async {
    await directory.create(recursive: true);
    final name =
        'background-${DateTime.now().millisecondsSinceEpoch}'
        '${_normalizedExtension(source.path)}';
    final destination = File(p.join(directory.path, name));
    await source.copy(destination.path);
    if (previousPath != null && previousPath != destination.path) {
      await delete(previousPath);
    }
    return destination.path;
  }

  /// 删除 [path] 指向的背景文件；路径为空、文件不存在或删除失败都静默忽略。
  ///
  /// 删除失败不影响「恢复默认背景」的语义：偏好已清除，界面即恢复默认背景。
  Future<void> delete(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 忽略：文件可能已被上一次替换删除，或所在目录不可写。
    }
  }

  String _normalizedExtension(String path) {
    final ext = p.extension(path).toLowerCase();
    return allowedExtensions.contains(ext.replaceFirst('.', '')) ? ext : '.png';
  }
}
