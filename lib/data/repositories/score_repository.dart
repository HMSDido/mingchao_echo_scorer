import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/util/file_names.dart';
import '../models/id_generator.dart';
import '../models/score_file.dart';
import 'load_result.dart';
import 'storage_service.dart';

/// 评分文件的读写。
///
/// 每个评分文件对应 `<scores>/<用户命名文件夹>/score.json`，即需求所说的
/// 「总分及各声骸评分保存在同一个自命名文件夹内」。文件夹名就是文件显示名，
/// 二者永远一致：读取时以磁盘上的文件夹名为准（自愈手工改名），写入时把
/// 名称规范化成合法文件夹名。
class ScoreRepository {
  ScoreRepository(this._storage);

  final StorageService _storage;

  static const String entryFileName = 'score.json';

  Directory folderOf(ScoreFile file) =>
      Directory(p.join(_storage.scoresDir.path, file.name));

  File entryOf(ScoreFile file) =>
      File(p.join(folderOf(file).path, entryFileName));

  /// 读取全部评分文件，按最近修改时间倒序。
  ///
  /// 各文件夹的读取互相独立，并发执行以缩短启动与每次重扫的耗时。
  Future<LoadResult<ScoreFile>> loadAll() async {
    final root = _storage.scoresDir;
    if (!await root.exists()) {
      return const LoadResult(items: [], errors: []);
    }

    final dirs = (await root.list().toList()).whereType<Directory>().toList();
    final results = await Future.wait(
      dirs.map((dir) async {
        final entry = File(p.join(dir.path, entryFileName));
        if (!await entry.exists()) {
          return (file: null, error: null);
        }
        try {
          final parsed = ScoreFile.fromJson(await _storage.readJson(entry));
          // 文件夹名是用户可见的真实名字，优先于 JSON 里可能过时的 name。
          return (
            file: parsed.copyWith(name: p.basename(dir.path)),
            error: null,
          );
        } catch (error) {
          return (file: null, error: '${p.basename(dir.path)}：$error');
        }
      }),
    );

    final byId = <String, ScoreFile>{};
    final errors = <String>[];
    for (final (file: file, error: error) in results) {
      if (error != null) {
        errors.add(error);
      } else if (file != null) {
        final previous = byId[file.id];
        if (previous == null || file.updatedAt.isAfter(previous.updatedAt)) {
          byId[file.id] = file;
        }
      }
    }

    final items = byId.values.toList()..sort(_compare);
    return LoadResult(items: items, errors: errors);
  }

  static int _compare(ScoreFile a, ScoreFile b) {
    final byTime = b.updatedAt.compareTo(a.updatedAt);
    return byTime != 0 ? byTime : a.name.compareTo(b.name);
  }

  /// 列出 scores 目录下已占用的文件夹名。
  Future<Set<String>> existingFolderNames() async {
    final root = _storage.scoresDir;
    if (!await root.exists()) return {};
    final names = <String>{};
    await for (final entity in root.list()) {
      if (entity is Directory) names.add(p.basename(entity.path));
    }
    return names;
  }

  /// 写入。返回落盘后的文件（name 可能因规范化/去重而与入参不同）。
  Future<ScoreFile> save(ScoreFile file) async {
    final folder = await _resolveFolder(file);
    final normalized = file.copyWith(name: folder, updatedAt: DateTime.now());
    await _storage.writeJsonAtomic(
      File(p.join(_storage.scoresDir.path, folder, entryFileName)),
      normalized.toJson(),
    );
    return normalized;
  }

  /// 为 [file] 解析出一个不会覆盖他人数据的文件夹名。
  Future<String> _resolveFolder(ScoreFile file) async {
    final desired = FileNames.sanitize(
      file.name.trim(),
      fallback: FileNames.sanitize(file.id, fallback: '未命名文件'),
    );
    final entry = File(p.join(_storage.scoresDir.path, desired, entryFileName));
    if (!await entry.exists()) return desired;
    try {
      final existing = ScoreFile.fromJson(await _storage.readJson(entry));
      if (existing.id == file.id) return desired; // 就是自己，正常覆盖
    } catch (_) {
      // 读不出来说明是坏文件，也不该静默覆盖，走去重。
    }
    final taken = await existingFolderNames();
    return FileNames.deduplicate(desired, taken);
  }

  /// 重命名文件（同时重命名磁盘文件夹）。
  Future<ScoreFile> rename(ScoreFile file, String newName) async {
    final desired = FileNames.sanitize(newName.trim(), fallback: file.name);
    if (desired == file.name) return file;

    final taken = await existingFolderNames();
    final folder = FileNames.deduplicate(desired, taken);
    final source = folderOf(file);
    final target = Directory(p.join(_storage.scoresDir.path, folder));
    if (await source.exists()) {
      await source.rename(target.path);
    }

    final renamed = file.copyWith(name: folder, updatedAt: DateTime.now());
    await _storage.writeJsonAtomic(entryOf(renamed), renamed.toJson());
    return renamed;
  }

  /// 删除文件及其整个文件夹。
  Future<void> delete(ScoreFile file) async {
    final folder = folderOf(file);
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  /// 把解析好的评分文件落盘为新的一份；文件夹名冲突时自动追加序号。
  Future<ScoreFile> importScoreFile(ScoreFile parsed, {String? name}) async {
    final desired = name?.trim().isNotEmpty == true
        ? name!.trim()
        : parsed.name;
    final taken = await existingFolderNames();
    final folder = FileNames.deduplicate(
      FileNames.sanitize(desired, fallback: '导入的评分文件'),
      taken,
    );
    var imported = parsed.copyWith(name: folder, updatedAt: DateTime.now());
    // id 来自不可信输入：与现有文件撞 id 会导致后续保存互相覆盖，换一个新的。
    final all = await loadAll();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(imported.id) ||
        all.items.any((item) => item.id == imported.id)) {
      imported = ScoreFile(
        id: newId(),
        name: imported.name,
        profileId: imported.profileId,
        profileName: imported.profileName,
        coefficients: imported.coefficients,
        echoes: imported.echoes,
        updatedAt: imported.updatedAt,
      );
    }
    await _storage.writeJsonAtomic(entryOf(imported), imported.toJson());
    return imported;
  }
}
