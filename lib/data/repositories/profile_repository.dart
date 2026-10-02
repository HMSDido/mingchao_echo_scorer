import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/util/file_names.dart';
import '../models/coefficient_profile.dart';
import '../models/id_generator.dart';
import 'load_result.dart';
import 'storage_service.dart';

/// 角色系数配置的读写。
///
/// 磁盘上以 `<profileId>.json` 命名：id 天然安全，且重命名配置时无需移动文件。
class ProfileRepository {
  ProfileRepository(this._storage);

  final StorageService _storage;

  /// 合法 id 的形状。id 会被拼进文件路径，而导入的 JSON 属于不可信输入，
  /// 因此必须挡住 `../` 之类的路径穿越。
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  static bool _isSafeId(String id) => _idPattern.hasMatch(id);

  File fileOf(CoefficientProfile profile) =>
      File(p.join(_storage.profilesDir.path, '${profile.id}.json'));

  /// 读取全部配置，按最近修改时间倒序（同时间按名称）。
  ///
  /// 各文件的读取互相独立，并发执行以缩短启动与每次重扫的耗时。
  Future<LoadResult<CoefficientProfile>> loadAll() async {
    final directory = _storage.profilesDir;
    if (!await directory.exists()) {
      return const LoadResult(items: [], errors: []);
    }

    final files = (await directory.list().toList())
        .whereType<File>()
        .where((entity) => entity.path.toLowerCase().endsWith('.json'))
        .toList();
    final results = await Future.wait(
      files.map((entity) async {
        try {
          final profile = CoefficientProfile.fromJson(
            await _storage.readJson(entity),
          );
          return (
            profile: _isSafeId(profile.id) ? profile : _withFreshId(profile),
            error: null,
          );
        } catch (error) {
          return (profile: null, error: '${p.basename(entity.path)}：$error');
        }
      }),
    );

    final items = <CoefficientProfile>[];
    final errors = <String>[];
    for (final (profile: profile, error: error) in results) {
      if (error != null) {
        errors.add(error);
      } else if (profile != null) {
        items.add(profile);
      }
    }
    items.sort(_compare);
    return LoadResult(items: items, errors: errors);
  }

  static CoefficientProfile _withFreshId(CoefficientProfile profile) =>
      CoefficientProfile(
        id: newId(),
        name: profile.name,
        coefficients: profile.coefficients,
        createdAt: profile.createdAt,
        updatedAt: profile.updatedAt,
      );

  static int _compare(CoefficientProfile a, CoefficientProfile b) {
    final byTime = b.updatedAt.compareTo(a.updatedAt);
    return byTime != 0 ? byTime : a.name.compareTo(b.name);
  }

  Future<CoefficientProfile?> findById(String id) async {
    if (!_isSafeId(id)) return null;
    final file = File(p.join(_storage.profilesDir.path, '$id.json'));
    if (!await file.exists()) return null;
    try {
      return CoefficientProfile.fromJson(await _storage.readJson(file));
    } catch (_) {
      return null;
    }
  }

  /// 写入（新建或更新）。名称会被规范化并去重，返回落盘后的配置。
  Future<CoefficientProfile> save(CoefficientProfile profile) async {
    final existing = await loadAll();
    final taken = existing.items
        .where((item) => item.id != profile.id)
        .map((item) => item.name);
    final safeName = FileNames.deduplicate(
      FileNames.sanitize(profile.name.trim(), fallback: '未命名配置'),
      taken,
    );
    final normalized = _isSafeId(profile.id)
        ? profile.copyWith(name: safeName, updatedAt: DateTime.now())
        : _withFreshId(profile)
              .copyWith(name: safeName, updatedAt: DateTime.now());
    await _storage.writeJsonAtomic(fileOf(normalized), normalized.toJson());
    return normalized;
  }

  Future<void> delete(String id) async {
    if (!_isSafeId(id)) return;
    final file = File(p.join(_storage.profilesDir.path, '$id.json'));
    if (await file.exists()) await file.delete();
  }

  /// 把解析好的配置落盘为新的一份；名称冲突时自动追加序号，
  /// id 不合法或已被占用时换新 id。
  Future<CoefficientProfile> importProfile(
    CoefficientProfile parsed, {
    String? name,
  }) async {
    final desired = name?.trim().isNotEmpty == true
        ? name!.trim()
        : parsed.name;
    final existing = await loadAll();
    final unique = FileNames.deduplicate(
      FileNames.sanitize(desired, fallback: '导入的配置'),
      existing.items.map((item) => item.name),
    );

    var imported = CoefficientProfile(
      id: parsed.id,
      name: unique,
      coefficients: parsed.coefficients,
      createdAt: parsed.createdAt,
      updatedAt: DateTime.now(),
    );
    if (!_isSafeId(imported.id) || await fileOf(imported).exists()) {
      imported = CoefficientProfile(
        id: newId(),
        name: imported.name,
        coefficients: imported.coefficients,
        createdAt: imported.createdAt,
        updatedAt: imported.updatedAt,
      );
    }
    await _storage.writeJsonAtomic(fileOf(imported), imported.toJson());
    return imported;
  }
}
