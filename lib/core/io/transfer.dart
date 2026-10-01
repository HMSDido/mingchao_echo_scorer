import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../util/file_names.dart';
import '../util/format.dart';

/// JSON 导入导出的文件对话框封装。
///
/// 全部走本地文件系统，不涉及任何网络请求。
class Transfer {
  const Transfer._();

  /// 让用户选择一个 `.json` 文件并解析为对象；取消选择返回 null。
  ///
  /// 内容不是合法 JSON 对象时抛 [FormatException]。
  static Future<Map<String, dynamic>?> pickJson({String? dialogTitle}) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle ?? '导入 JSON',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = result?.files.singleOrNull?.path;
    if (path == null) return null;

    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('文件顶层不是 JSON 对象：${p.basename(path)}');
    }
    return decoded;
  }

  /// 导出 JSON 对象，返回实际写入的路径；用户取消返回 null。
  ///
  /// 桌面端弹出「另存为」对话框；拿不到路径时（例如 Android 上插件不支持
  /// 返回路径）退回写入 [fallbackDir] 并把路径回传给调用方展示。
  static Future<String?> saveJson({
    required String suggestedName,
    required Object json,
    required Directory fallbackDir,
  }) async {
    final encoded = const JsonEncoder.withIndent('  ').convert(json);
    final fileName =
        '${FileNames.sanitize(suggestedName, fallback: 'export')}.json';

    String? target;
    try {
      target = await FilePicker.platform.saveFile(
        dialogTitle: '导出 JSON',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(encoded)),
      );
    } on Exception {
      target = null;
    }

    if (target == null || target.trim().isEmpty) {
      await fallbackDir.create(recursive: true);
      final taken = await _existingNames(fallbackDir);
      final stamped = FileNames.deduplicate(
        '${p.basenameWithoutExtension(fileName)}-${Format.timestamp(DateTime.now())}',
        taken,
      );
      final file = File(p.join(fallbackDir.path, '$stamped.json'));
      await file.writeAsString(encoded);
      return file.path;
    }

    if (!target.toLowerCase().endsWith('.json')) target = '$target.json';
    final file = File(target);
    await file.parent.create(recursive: true);
    await file.writeAsString(encoded);
    return file.path;
  }

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

  static Future<Set<String>> _existingNames(Directory dir) async {
    if (!await dir.exists()) return {};
    final names = <String>{};
    await for (final entity in dir.list()) {
      names.add(p.basenameWithoutExtension(entity.path));
    }
    return names;
  }
}
