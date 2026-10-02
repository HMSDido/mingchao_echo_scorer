import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/coefficient_profile.dart';
import '../data/models/echo_entry.dart';
import '../data/models/score_file.dart';
import '../data/models/share_link.dart';
import '../data/repositories/score_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/storage_service.dart';
import 'library_layout.dart';

/// 主区域当前显示的页面。
enum ShellView { files, profiles, settings, storage, theme, about }

/// 页面级「离开守卫」：返回 true 表示允许离开。
///
/// 声骸详情页用它把「未保存的草稿」纳入窗口关闭前的统一询问。
typedef LeaveGuard = Future<bool> Function();

/// 已打开的评分文件、当前显示的文件、脏状态，以及磁盘列表。
///
/// 脏检查基于「与最近一次落盘内容的语义比较」，因此改了又改回去不算脏，
/// 关闭时不会打扰用户（对应需求「没有改动直接关闭则不提醒，类似 Word」）。
class WorkspaceController extends ChangeNotifier {
  WorkspaceController(this._repo, this._storage, SettingsRepository settings)
    : _settings = settings,
      _layout = LibraryLayout(
        idPrefix: 's:',
        tokens: settings.scoreLayoutTokens,
      ),
      _expanded = {...settings.scoreExpandedGroups};

  final ScoreRepository _repo;
  final StorageService _storage;
  final SettingsRepository _settings;
  final LibraryLayout _layout;

  /// 展开的分组集合：**默认全部折叠**，这里存的是例外（展开的那几个）。
  final Set<String> _expanded;

  final List<LeaveGuard> _guards = [];

  List<ScoreFile> _diskFiles = const [];
  List<String> _diskErrors = const [];
  final List<ScoreFile> _open = [];
  final Map<String, ScoreFile> _baseline = {};

  String? _activeId;
  ShellView _view = ShellView.files;
  String _query = '';
  bool _loading = true;

  bool get loading => _loading;

  ShellView get view => _view;

  String get fileQuery => _query;

  /// 磁盘上的全部评分文件（按最近修改倒序）。
  List<ScoreFile> get diskFiles => _diskFiles;

  /// 读取失败的条目（坏文件不会中断整个列表）。
  List<String> get diskErrors => _diskErrors;

  /// 已打开的文件，最近使用的排在前。
  List<ScoreFile> get openFiles => List.unmodifiable(_open);

  /// 文件栏中实际显示的文件（受搜索框过滤）。
  List<ScoreFile> get visibleOpenFiles {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return openFiles;
    return _open
        .where((file) => file.name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  // ---------------------------------------------------------------- 分组布局

  /// 展示用的布局行：组标题与文件 id 混排，未收录的新文件补在根层末尾。
  ///
  /// 收起的组只保留组标题（默认折叠）；组内文件数请用 [layoutGroupMemberIds]。
  /// 搜索时界面退回 [visibleOpenFiles] 的扁平列表，不走这里。
  List<LayoutNode> get layoutRows =>
      _layout.collapsedView([for (final file in _open) file.id], _expanded);

  /// 组内的文件 id（清空组、导出本组、组内文件数时用）。
  ///
  /// 过滤掉磁盘上已不存在的残留 token，计数与实际操作都以现有文件为准。
  List<String> layoutGroupMemberIds(String name) {
    final live = {for (final file in _open) file.id};
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
    // 文件被拖进（或留在）某个组后，把该组展开，否则用户看不到拖入的结果。
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

  /// 删除分组本身：组内文件不删，释放到根层。
  void deleteLayoutGroup(String name) {
    _syncLayout();
    _layout.deleteGroup(name);
    _expanded.remove(name);
    _persistLayout();
    _persistExpanded();
    notifyListeners();
  }

  /// 把文件放进指定分组（组内新建时用）。
  void placeInLayoutGroup(String name, String fileId) {
    _syncLayout();
    _layout.insertIntoGroup(name, fileId);
    _expanded.add(name);
    _persistLayout();
    _persistExpanded();
    notifyListeners();
  }

  void _syncLayout() => _layout.mergeWith([for (final file in _open) file.id]);

  void _persistLayout() => _settings.setScoreLayoutTokens(_layout.tokens);

  void _persistExpanded() =>
      _settings.setScoreExpandedGroups(_expanded.toList());

  ScoreFile? get activeFile => byId(_activeId);

  ScoreFile? byId(String? id) {
    if (id == null) return null;
    for (final file in _open) {
      if (file.id == id) return file;
    }
    return null;
  }

  bool isActive(ScoreFile file) => file.id == _activeId;

  bool isOpen(ScoreFile file) => byId(file.id) != null;

  /// 相对最近一次落盘是否有未保存的改动。
  bool isDirty(ScoreFile file) {
    final saved = _baseline[file.id];
    if (saved == null) return true;
    return !file.sameContentAs(saved);
  }

  List<ScoreFile> get dirtyFiles =>
      _open.where(isDirty).toList(growable: false);

  bool get hasUnsavedChanges => dirtyFiles.isNotEmpty;

  // ---------------------------------------------------------------- 生命周期

  /// 启动时读取磁盘数据，并恢复上次退出时打开的文件。
  Future<void> bootstrap() async {
    await _storage.ensureStructure();
    await reloadDisk();
    for (final id in _settings.lastOpenFileIds) {
      final file = _diskFiles.where((item) => item.id == id).firstOrNull;
      if (file != null) _addOpen(file);
    }
    if (_open.isEmpty && _diskFiles.isNotEmpty) _addOpen(_diskFiles.first);
    _activeId = _open.isEmpty ? null : _open.first.id;
    _loading = false;
    notifyListeners();
  }

  /// 重新扫描磁盘（不改动已打开文件的内存状态）。
  Future<void> reloadDisk() async {
    final result = await _repo.loadAll();
    _diskFiles = result.items;
    _diskErrors = result.errors;
  }

  /// 重新扫描磁盘并通知界面（「打开文件」对话框用）。
  Future<void> refreshDisk() async {
    await reloadDisk();
    notifyListeners();
  }

  /// 存储根目录被切换：丢弃当前打开的文件，重新扫描新目录。
  Future<void> resetForNewRoot() async {
    _open.clear();
    _baseline.clear();
    _activeId = null;
    _view = ShellView.files;
    _loading = true;
    notifyListeners();
    await reloadDisk();
    _loading = false;
    notifyListeners();
  }

  // -------------------------------------------------------------------- 视图

  void show(ShellView view) {
    if (_view == view) return;
    _view = view;
    notifyListeners();
  }

  void setFileQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  /// 切换主界面显示的文件。**不提示保存** —— 文件并没有被关闭。
  void select(String id) {
    if (byId(id) == null) return;
    final changed = _activeId != id;
    _activeId = id;
    _moveToFront(id);
    final viewChanged = _view != ShellView.files;
    _view = ShellView.files;
    if (!changed && !viewChanged) return;
    unawaited(_persistLastOpen());
    notifyListeners();
  }

  void _moveToFront(String id) {
    final index = _open.indexWhere((file) => file.id == id);
    if (index > 0) _open.insert(0, _open.removeAt(index));
  }

  // -------------------------------------------------------------- 文件操作

  /// 新建评分文件：立即落盘并打开，随后由总览页引导「选择角色」。
  ///
  /// [inGroup] 非空时，新文件直接插进该分组的组头下。
  Future<ScoreFile> createFile(String name, {String? inGroup}) async {
    final created = await _repo.save(ScoreFile.empty(name: name));
    await reloadDisk();
    _addOpen(created);
    if (inGroup != null) {
      _layout.insertIntoGroup(inGroup, created.id);
      _expanded.add(inGroup);
      _persistExpanded();
    }
    _persistLayout();
    _activeId = created.id;
    _view = ShellView.files;
    unawaited(_persistLastOpen());
    notifyListeners();
    return created;
  }

  /// 打开一个已在磁盘上的文件（已经打开则只是切换到它）。
  void openFile(ScoreFile file) {
    if (byId(file.id) != null) {
      select(file.id);
      return;
    }
    _addOpen(file);
    _activeId = file.id;
    _view = ShellView.files;
    unawaited(_persistLastOpen());
    notifyListeners();
  }

  /// 写入内存改动（标记为脏，不落盘）。
  void updateFile(ScoreFile next) {
    final index = _open.indexWhere((file) => file.id == next.id);
    if (index < 0) return;
    _open[index] = next;
    notifyListeners();
  }

  void updateEcho(String fileId, EchoEntry echo) {
    final file = byId(fileId);
    if (file == null) return;
    updateFile(file.withEcho(echo));
  }

  void renameEcho(String fileId, int slot, String name) {
    final file = byId(fileId);
    if (file == null) return;
    updateFile(file.withEcho(file.echoAt(slot).copyWith(name: name)));
  }

  /// 把角色系数快照套用到文件（新建后「选择角色」，或之后「更换角色」）。
  void applyProfile(ScoreFile file, CoefficientProfile profile) =>
      updateFile(file.applyingProfile(profile));

  /// 落盘单个文件。文件夹名可能被规范化/去重，因此以仓库返回值为准。
  Future<void> saveFile(ScoreFile file) async {
    _adopt(await _repo.save(file));
    await reloadDisk();
    notifyListeners();
  }

  Future<void> saveActive() async {
    final file = activeFile;
    if (file != null) await saveFile(file);
  }

  /// 保存全部有改动的文件（窗口关闭前的「全部保存」）。
  ///
  /// 逐个落盘但只在最后重扫一次磁盘：每次保存都全量重读会在文件多时
  /// 变成 k×n 次读，关闭窗口会明显变慢。
  Future<void> saveAll() async {
    final dirty = List.of(dirtyFiles);
    for (final file in dirty) {
      _adopt(await _repo.save(file));
    }
    if (dirty.isNotEmpty) {
      await reloadDisk();
      notifyListeners();
    }
  }

  /// 重命名文件：磁盘文件夹同步改名，改动会一并落盘。
  Future<void> renameFile(ScoreFile file, String newName) async {
    _adopt(await _repo.rename(file, newName));
    await reloadDisk();
    notifyListeners();
  }

  /// 关闭文件（调用方负责先处理未保存改动）。
  Future<void> closeFile(ScoreFile file) async {
    _open.removeWhere((item) => item.id == file.id);
    _baseline.remove(file.id);
    if (_activeId == file.id) {
      _activeId = _open.isEmpty ? null : _open.first.id;
    }
    unawaited(_persistLastOpen());
    notifyListeners();
  }

  /// 从磁盘删除文件并关闭。
  Future<void> deleteFile(ScoreFile file) async {
    await _repo.delete(file);
    _open.removeWhere((item) => item.id == file.id);
    _baseline.remove(file.id);
    if (_activeId == file.id) {
      _activeId = _open.isEmpty ? null : _open.first.id;
    }
    await reloadDisk();
    unawaited(_persistLastOpen());
    notifyListeners();
  }

  /// 批量从磁盘删除文件并关闭，最后只重扫一次磁盘。
  ///
  /// 返回删除失败的条目（坏文件夹不该中断整批）。
  Future<List<ScoreFile>> deleteFiles(Iterable<ScoreFile> files) async {
    final failed = <ScoreFile>[];
    for (final file in files) {
      try {
        await _repo.delete(file);
      } on Exception {
        failed.add(file);
        continue;
      }
      _open.removeWhere((item) => item.id == file.id);
      _baseline.remove(file.id);
      if (_activeId == file.id) _activeId = null;
    }
    _activeId ??= _open.isEmpty ? null : _open.first.id;
    await reloadDisk();
    unawaited(_persistLastOpen());
    notifyListeners();
    return failed;
  }

  /// 导入剪贴板文本（分享链接或裸 JSON，可多行批量）。
  ///
  /// 坏行只记进 failures，其余文件照常落盘并打开；最后统一重扫一次磁盘。
  Future<ShareImportSummary> importShareText(String raw) async {
    final parsed = ScoreShare.parse(raw);
    final failures = List<String>.of(parsed.failures);
    final imported = <ScoreFile>[];
    for (final file in parsed.items) {
      try {
        imported.add(await _repo.importScoreFile(file));
      } on Exception catch (error) {
        failures.add('「${file.name}」：$error');
      }
    }
    await reloadDisk();
    for (final file in imported) {
      _addOpen(file);
    }
    if (imported.isNotEmpty) {
      _activeId = imported.last.id;
      _view = ShellView.files;
    }
    unawaited(_persistLastOpen());
    notifyListeners();
    return (imported: imported.length, failures: failures);
  }

  // ------------------------------------------------------------------ 守卫

  /// 注册一个离开守卫，返回注销函数。
  void Function() registerGuard(LeaveGuard guard) {
    _guards.add(guard);
    return () => _guards.remove(guard);
  }

  /// 依次询问所有守卫；任一拒绝则返回 false。
  Future<bool> runGuards() async {
    for (final guard in List.of(_guards)) {
      if (!await guard()) return false;
    }
    return true;
  }

  // ------------------------------------------------------------------ 内部

  void _addOpen(ScoreFile file) {
    _open.removeWhere((item) => item.id == file.id);
    _open.insert(0, file);
    _baseline[file.id] = file;
  }

  /// 用落盘后的版本替换内存中的文件，并把它作为新的脏检查基线。
  void _adopt(ScoreFile saved) {
    final index = _open.indexWhere((file) => file.id == saved.id);
    if (index >= 0) {
      _open[index] = saved;
    } else {
      _open.insert(0, saved);
    }
    _baseline[saved.id] = saved;
    if (_activeId == null || _activeId == saved.id) _activeId = saved.id;
    unawaited(_persistLastOpen());
  }

  Future<void> _persistLastOpen() =>
      _settings.setLastOpenFileIds(_open.map((file) => file.id).toList());
}
