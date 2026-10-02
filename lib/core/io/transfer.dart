import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// 系统文件对话框封装：选目录、选图片。
///
/// 全部走本地文件系统，不涉及任何网络请求。JSON 的导入导出已改为剪贴板
/// 分享链接（见 `ShareLink`），不再经过文件对话框。
class Transfer {
  const Transfer._();

  /// 让用户选择一个目录；取消返回 null。
  static Future<String?> pickDirectory({String? dialogTitle}) =>
      FilePicker.platform.getDirectoryPath(dialogTitle: dialogTitle ?? '选择文件夹');

  /// 让用户选择一张本地图片（jpg/jpeg/png/webp）；取消返回 null。
  ///
  /// 只返回文件句柄，复制进应用私有目录由 `BackgroundImageService` 负责。
  static Future<File?> pickImage({String? dialogTitle}) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle ?? '选择背景图片',
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    final path = result?.files.singleOrNull?.path;
    return path == null ? null : File(path);
  }
}
