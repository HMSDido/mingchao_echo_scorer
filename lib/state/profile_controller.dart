import 'package:flutter/foundation.dart';

import '../data/models/coefficient_profile.dart';
import '../data/models/share_link.dart';
import '../data/repositories/profile_repository.dart';

/// 角色系数配置的列表状态与增删改查。
class ProfileController extends ChangeNotifier {
  ProfileController(this._repo);

  final ProfileRepository _repo;

  List<CoefficientProfile> _profiles = const [];
  List<String> _errors = const [];

  List<CoefficientProfile> get profiles => _profiles;

  /// 读取失败的条目（坏文件不会中断整个列表）。
  List<String> get errors => _errors;

  CoefficientProfile? byId(String id) {
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Future<void> reload() async {
    final result = await _repo.loadAll();
    _profiles = result.items;
    _errors = result.errors;
    notifyListeners();
  }

  /// 新建一份全 0 系数的配置并落盘。
  Future<CoefficientProfile> create(String name) =>
      _commit(CoefficientProfile.create(name));

  Future<CoefficientProfile> save(CoefficientProfile profile) =>
      _commit(profile);

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await reload();
  }

  /// 批量删除，最后只刷新一次列表；返回删除失败的 id。
  Future<List<String>> deleteMany(Iterable<CoefficientProfile> profiles) async {
    final failed = <String>[];
    for (final profile in profiles) {
      try {
        await _repo.delete(profile.id);
      } on Exception {
        failed.add(profile.id);
      }
    }
    await reload();
    return failed;
  }

  /// 导入剪贴板文本（分享链接或裸 JSON，可多行批量）。
  ///
  /// 坏行只记进 failures，其余配置照常逐条落盘，最后统一刷新一次列表。
  Future<ShareImportSummary> importShareText(String raw) async {
    final parsed = ProfileShare.parse(raw);
    final failures = List<String>.of(parsed.failures);
    var imported = 0;
    for (final profile in parsed.items) {
      try {
        await _repo.importProfile(profile);
        imported++;
      } on Exception catch (error) {
        failures.add('「${profile.name}」：$error');
      }
    }
    await reload();
    return (imported: imported, failures: failures);
  }

  Future<CoefficientProfile> _commit(CoefficientProfile profile) async {
    final saved = await _repo.save(profile);
    await reload();
    return saved;
  }
}
