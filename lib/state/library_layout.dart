/// 列表分组布局（角色系数配置 / 评分文件共用）：一条「组标题 + 条目 id」混排的扁平序列。
///
/// 采用「位置模型」：分组归属与顺序完全由序列中相邻的组标题与条目位置表达，
/// 数据模型本身不带分组字段；布局只持久化到 prefs，是本地界面偏好，
/// 不随分享链接导出，也不会把文件弄脏。
typedef LayoutNode = ({bool isGroup, String value});

LayoutNode _group(String name) => (isGroup: true, value: name);

LayoutNode _item(String id) => (isGroup: false, value: id);

class LibraryLayout {
  LibraryLayout({required this.idPrefix, List<String> tokens = const []})
    : _nodes = [] {
    final seenGroups = <String>{};
    final seenIds = <String>{};
    for (final token in tokens) {
      if (token.startsWith(_groupPrefix)) {
        final name = token.substring(_groupPrefix.length);
        if (name.isNotEmpty && seenGroups.add(name)) {
          _nodes.add(_group(name));
        }
      } else if (token.startsWith(idPrefix) && token.length > idPrefix.length) {
        final id = token.substring(idPrefix.length);
        if (seenIds.add(id)) _nodes.add(_item(id));
      }
    }
  }

  static const String _groupPrefix = 'g:';

  /// 条目 id 的前缀（如 `p:` / `s:`），把两个命名空间和组标题区分开。
  final String idPrefix;

  final List<LayoutNode> _nodes;

  /// 与布局行一一对应的序列化 token 序列，直接写入 prefs。
  List<String> get tokens => [
    for (final node in _nodes)
      if (node.isGroup)
        '$_groupPrefix${node.value}'
      else
        '$idPrefix${node.value}',
  ];

  int get rowCount => _nodes.length;

  bool rowIsGroup(int index) => _nodes[index].isGroup;

  /// 组名或条目 id，取决于 [rowIsGroup]。
  String rowValue(int index) => _nodes[index].value;

  List<String> get groupNames => _nodes
      .where((node) => node.isGroup)
      .map((node) => node.value)
      .toList(growable: false);

  bool hasGroup(String name) =>
      _nodes.any((node) => node.isGroup && node.value == name);

  /// 组内成员 id（按布局顺序）；组不存在时为空。
  List<String> groupMemberIds(String name) {
    final h = _headerIndex(name);
    if (h < 0) return const [];
    return [
      for (var i = h + 1; i < _groupEnd(h); i++)
        if (!_nodes[i].isGroup) _nodes[i].value,
    ];
  }

  /// 根层成员 id：排在第一个组标题之前的连续条目区。
  List<String> get rootItemIds {
    final first = _nodes.indexWhere((node) => node.isGroup);
    return [
      for (final node in _nodes.sublist(0, first < 0 ? _nodes.length : first))
        node.value,
    ];
  }

  // ---------------------------------------------------------------- 组操作

  /// 在列表末尾新建分组；名字为空或重复时不改动并返回 false。
  bool addGroup(String name) {
    if (name.trim().isEmpty || hasGroup(name)) return false;
    _nodes.add(_group(name));
    return true;
  }

  bool renameGroup(String name, String newName) {
    final h = _headerIndex(name);
    if (h < 0) return false;
    if (newName.trim().isEmpty) return false;
    if (newName != name && hasGroup(newName)) return false;
    _nodes[h] = _group(newName);
    return true;
  }

  /// 删除分组本身，不删成员：成员整体释放到根层末尾。
  void deleteGroup(String name) {
    final h = _headerIndex(name);
    if (h < 0) return;
    final end = _groupEnd(h);
    final members = _nodes.sublist(h + 1, end);
    _nodes.removeRange(h, end);
    _nodes.insertAll(_rootInsertIndex, members);
  }

  /// 把条目插入组头（组内新建）；条目原在布局其他位置时移过来。
  bool insertIntoGroup(String name, String id) {
    _removeItem(id);
    final h = _headerIndex(name);
    if (h < 0) return false;
    _nodes.insert(h + 1, _item(id));
    return true;
  }

  /// 把条目追加到根层末尾；条目原在布局其他位置时移过来。
  void appendToRoot(String id) {
    _removeItem(id);
    _nodes.insert(_rootInsertIndex, _item(id));
  }

  // ---------------------------------------------------------------- 重排

  /// 按 [ReorderableListView.onReorderItem] 的索引语义重排扁平行：
  /// [insertIndex] 已是「移除被拖行之后」列表中的落点下标。
  ///
  /// 拖动组标题时整组（标题 + 成员）一起移动；落点仍在原组范围内不生效。
  void moveNode(int oldIndex, int insertIndex) {
    if (!rowIsGroup(oldIndex)) {
      if (insertIndex == oldIndex) return;
      _nodes.insert(insertIndex, _nodes.removeAt(oldIndex));
      return;
    }
    final end = _groupEnd(oldIndex);
    if (insertIndex >= oldIndex && insertIndex <= end - 1) return;
    final block = _nodes.sublist(oldIndex, end);
    _nodes.removeRange(oldIndex, end);
    final insertAt = insertIndex < oldIndex
        ? insertIndex
        : insertIndex - block.length + 1;
    _nodes.insertAll(insertAt, block);
  }

  /// 与当前存在的条目对账：布局里已不存在的条目丢弃；
  /// 布局未覆盖的新条目按 [liveIds] 给出的顺序追加到根层末尾。
  void mergeWith(List<String> liveIds) {
    final merged = viewWith(liveIds);
    _nodes
      ..clear()
      ..addAll(merged);
  }

  /// 展示用的布局行（不改动布局本身）：丢弃已不存在的条目，
  /// 布局尚未覆盖的新条目按 [liveIds] 顺序补到根层末尾。
  List<LayoutNode> viewWith(List<String> liveIds) {
    final live = liveIds.toSet();
    final view = [
      for (final node in _nodes)
        if (node.isGroup || live.contains(node.value)) node,
    ];
    final known = {
      for (final node in view)
        if (!node.isGroup) node.value,
    };
    final missing = [
      for (final id in liveIds)
        if (!known.contains(id)) _item(id),
    ];
    if (missing.isEmpty) return view;
    final first = view.indexWhere((node) => node.isGroup);
    view.insertAll(first < 0 ? view.length : first, missing);
    return view;
  }

  // ---------------------------------------------------------------- 内部

  int get _rootInsertIndex {
    final first = _nodes.indexWhere((node) => node.isGroup);
    return first < 0 ? _nodes.length : first;
  }

  int _headerIndex(String name) =>
      _nodes.indexWhere((node) => node.isGroup && node.value == name);

  /// 组的结束下标（不含）：从组标题起向下，直到下一个组标题或列表末尾。
  int _groupEnd(int headerIndex) {
    var i = headerIndex + 1;
    while (i < _nodes.length && !_nodes[i].isGroup) {
      i++;
    }
    return i;
  }

  void _removeItem(String id) =>
      _nodes.removeWhere((node) => !node.isGroup && node.value == id);
}
