import 'package:flutter/foundation.dart';

import '../data/models/coefficient_profile.dart';
import '../data/models/share_link.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/settings_repository.dart';
import 'library_layout.dart';

/// 角色系数配置的列表状态与增删改查。
class ProfileController extends ChangeNotifier {
  ProfileController(this._repo, {SettingsRepository? layoutStore})
    : _layoutStore = layoutStore,
      _layout = LibraryLayout(
        idPrefix: 'p:',
        tokens: layoutStore?.profileLayoutTokens ?? const [],
      ),
      _expanded = {...?layoutStore?.profileExpandedGroups};

  final ProfileRepository _repo;
  final SettingsRepository? _layoutStore;
  final LibraryLayout _layout;

  /// 展开的分组集合：**默认全部折叠**，这里存的是例外（展开的那几个）。
  final Set<String> _expanded;

  List<CoefficientProfile> _profiles = const [];
  List<String> _errors = const [];

  List<CoefficientProfile> get profiles => _profiles;

  /// 读取失败的条目（坏文件不会中断整个列表）。
  List<String> get errors => _errors;

  // ---------------------------------------------------------------- 布局

  /// 展示用的布局行：组标题与配置 id 混排，未收录的新配置补在根层末尾。
  ///
  /// 收起的组只保留组标题（默认折叠）；组内配置数请用 [layoutGroupMemberIds]。
  List<LayoutNode> get layoutRows =>
      _layout.collapsedView([for (final p in _profiles) p.id], _expanded);

  /// 「选择角色」弹窗用的未折叠布局行：组归属照实给出，
  /// 折叠状态由弹窗自己按会话内的展开集合处理（默认收起，不写 prefs）。
  List<LayoutNode> get pickerLayoutRows =>
      _layout.viewWith([for (final p in _profiles) p.id]);

  /// 组内的配置 id（清空组、导出本组、组内配置数时用）。
  ///
  /// 过滤掉磁盘上已不存在的残留 token，计数与实际操作都以现有配置为准。
  List<String> layoutGroupMemberIds(String name) {
    final live = {for (final p in _profiles) p.id};
    return _layout
        .groupMemberIds(name)
        .where(live.contains)
        .toList(growable: false);
  }

  bool isGroupExpanded(String name) => _expanded.contains(name);

  /// 切换组的折叠状态（点组头）。
  void toggleLayoutGroup(String name) {
    if (!_expanded.remove(name)) _expanded.add(name);
    _persistExpanded();
    notifyListeners();
  }

  void moveLayoutRow(int oldIndex, int newIndex) {
    _syncLayout();
    final view = layoutRows;
    if (oldIndex < 0 || oldIndex >= view.length) return;
    final dragged = view[oldIndex];
    _layout.moveNodeInView(view, oldIndex, newIndex);
    final target = _layout.groupOf(dragged.value);
    if (target != null && !_expanded.contains(target)) {
      _expanded.add(target);
      _persistExpanded();
    }
    _persistLayout();
    notifyListeners();
  }

  bool addLayoutGroup(String name) {
    _syncLayout();
    if (!_layout.addGroup(name)) return false;
    _persistLayout();
    notifyListeners();
    return true;
  }

  bool renameLayoutGroup(String name, String newName) {
    _syncLayout();
    if (!_layout.renameGroup(name, newName)) return false;
    if (_expanded.remove(name)) _expanded.add(newName);
    _persistLayout();
    _persistExpanded();
    notifyListeners();
    return true;
  }

  /// 删除分组本身：组内配置不删，释放到根层。
  void deleteLayoutGroup(String name) {
    _syncLayout();
    _layout.deleteGroup(name);
    _expanded.remove(name);
    _persistLayout();
    _persistExpanded();
    notifyListeners();
  }

  /// 把配置放进指定分组（组内新建时用）。
  void placeInLayoutGroup(String name, String profileId) {
    _syncLayout();
    _layout.insertIntoGroup(name, profileId);
    _expanded.add(name);
    _persistLayout();
    _persistExpanded();
    notifyListeners();
  }

  void _syncLayout() => _layout.mergeWith([for (final p in _profiles) p.id]);

  void _persistLayout() => _layoutStore?.setProfileLayoutTokens(_layout.tokens);

  void _persistExpanded() =>
      _layoutStore?.setProfileExpandedGroups(_expanded.toList());

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
