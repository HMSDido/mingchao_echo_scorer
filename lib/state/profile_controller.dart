import 'package:flutter/foundation.dart';

import '../data/models/coefficient_profile.dart';
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

  /// 从导入的 JSON 建立配置。
  Future<CoefficientProfile> importJson(Map<String, dynamic> json) async {
    final imported = await _repo.importFromJson(json);
    await reload();
    return imported;
  }

  Future<CoefficientProfile> _commit(CoefficientProfile profile) async {
    final saved = await _repo.save(profile);
    await reload();
    return saved;
  }
}
