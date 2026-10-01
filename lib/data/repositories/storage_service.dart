import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 本地存储根目录与目录结构的统一管理。
///
/// 目录布局：
/// ```
/// <root>/
///   profiles/<profileId>.json      角色系数配置
///   scores/<用户命名文件夹>/score.json  评分文件
///   exports/                       无可用保存对话框时的兜底导出目录
/// ```
class StorageService {
  StorageService(this._root);

  Directory _root;

  Directory get root => _root;

  Directory get profilesDir => Directory(p.join(_root.path, 'profiles'));

  Directory get scoresDir => Directory(p.join(_root.path, 'scores'));

  Directory get exportsDir => Directory(p.join(_root.path, 'exports'));

  /// 创建全部目录（幂等）。
  Future<void> ensureStructure() async {
    await _root.create(recursive: true);
    await profilesDir.create(recursive: true);
    await scoresDir.create(recursive: true);
    await exportsDir.create(recursive: true);
  }

  /// 切换存储根目录并初始化其结构。
  Future<void> changeRoot(Directory next) async {
    _root = next;
    await ensureStructure();
  }

  /// 读取 JSON 对象；内容非法时抛 [FormatException]。
  Future<Map<String, dynamic>> readJson(File file) async {
    final text = await file.readAsString();
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('JSON 顶层不是对象：${file.path}');
    }
    return decoded;
  }

  /// 先写临时文件再原子替换，避免写盘过程中断导致数据损坏。
  Future<void> writeJsonAtomic(File file, Object json) async {
    await file.parent.create(recursive: true);
    final temp = File(
      p.join(
        file.parent.path,
        '${p.basename(file.path)}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await temp.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    try {
      await temp.rename(file.path);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  /// 解析平台默认根目录。
  ///
  /// * Windows：`文档\mingchao_echo_scorer`
  /// * Android：应用私有外部目录（受 SAF 限制，双端同步靠 JSON 导入导出）
  static Future<Directory> resolveDefaultRoot() async {
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        return Directory(p.join(external.path, 'mingchao_echo_scorer'));
      }
    }
    final documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'mingchao_echo_scorer'));
  }

  /// 由用户在设置里指定的路径解析根目录；路径为空时回退到默认位置。
  static Future<Directory> resolveRoot(String? customPath) async {
    final trimmed = customPath?.trim() ?? '';
    if (trimmed.isEmpty) return resolveDefaultRoot();
    return Directory(trimmed);
  }
}
