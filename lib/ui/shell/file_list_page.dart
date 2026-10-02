import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/util/format.dart';
import '../../data/models/score_file.dart';
import '../../domain/score_calculator.dart';
import '../../state/workspace_controller.dart';
import '../actions/file_actions.dart';

/// 窄屏（安卓）的标签页列表：顶栏「标签页」按钮推入的全屏文件列表。
///
/// 桌面端仍用侧边文件栏；窄屏把「切到哪个文件」收到这一页里，
/// 点一行即切换并返回列表，行尾直接放分享 / 重命名 / 删除三个常用操作，
/// 其余动作收进本页顶栏的 ⋮ 菜单，避免在主界面堆一整排功能键。
///
/// 与宽屏文件栏共用一套分组布局：无搜索词时是可拖拽的分组列表，
/// 搜索时退回扁平过滤结果。
class FileListPage extends StatefulWidget {
  const FileListPage({super.key});

  @override
  State<FileListPage> createState() => _FileListPageState();
}

class _FileListPageState extends State<FileListPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    context.read<WorkspaceController>().setFileQuery(value);
  }

  void _clearSearch() {
    _search.clear();
    context.read<WorkspaceController>().setFileQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final files = workspace.visibleOpenFiles;
    if (_search.text != workspace.fileQuery) {
      _search
        ..text = workspace.fileQuery
        ..selection = TextSelection.collapsed(
          offset: workspace.fileQuery.length,
        );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('评分文件'),
        actions: [
          IconButton(
            tooltip: '新建评分文件',
            icon: const Icon(Icons.note_add_outlined),
            onPressed: () => FileActions.create(context),
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) {
              switch (value) {
                case 'newGroup':
                  FileActions.addGroup(context);
                case 'open':
                  FileActions.open(context);
                case 'import':
                  FileActions.importFromClipboard(context);
                case 'copyAll':
                  FileActions.copyAllShareLinks(context);
                case 'deleteMany':
                  FileActions.deleteMany(context);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'newGroup', child: Text('新建分组')),
              PopupMenuItem(value: 'open', child: Text('打开已有文件')),
              PopupMenuItem(value: 'import', child: Text('粘贴导入')),
              PopupMenuItem(value: 'copyAll', child: Text('复制全部分享链接')),
              PopupMenuItem(value: 'deleteMany', child: Text('批量删除')),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: '搜索文件名',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: workspace.fileQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _clearSearch,
                      ),
              ),
            ),
          ),
          Expanded(
            child: () {
              final searching = workspace.fileQuery.trim().isNotEmpty;
              if (searching) {
                return files.isEmpty
                    ? const _EmptyState(searching: true, hasOpen: true)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                        itemCount: files.length,
                        itemBuilder: (context, index) =>
                            _FileRow(file: files[index]),
                      );
              }
              final rows = workspace.layoutRows;
              if (rows.isEmpty) {
                return _EmptyState(
                  searching: false,
                  hasOpen: workspace.openFiles.isNotEmpty,
                );
              }
              return ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                buildDefaultDragHandles: false,
                itemCount: rows.length,
                onReorderItem: (oldIndex, newIndex) =>
                    workspace.moveLayoutRow(oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  if (row.isGroup) {
                    return _GroupRow(
                      key: ValueKey('g:${row.value}'),
                      index: index,
                      name: row.value,
                      memberCount: _groupSize(rows, index),
                    );
                  }
                  final file = workspace.byId(row.value);
                  if (file == null) {
                    return SizedBox.shrink(key: ValueKey('ghost-$index'));
                  }
                  return _FileRow(
                    key: ValueKey('s:${file.id}'),
                    index: index,
                    file: file,
                  );
                },
              );
            }(),
          ),
          if (workspace.diskErrors.isNotEmpty)
            _ErrorBanner(messages: workspace.diskErrors),
        ],
      ),
    );
  }
}

/// 布局里某个组标题后面的连续条目数（组内文件数）。
int _groupSize(List<({bool isGroup, String value})> rows, int headerIndex) {
  var count = 0;
  for (var i = headerIndex + 1; i < rows.length && !rows[i].isGroup; i++) {
    count++;
  }
  return count;
}

/// 窄屏列表的分组标题行：拖把手 / 长按移动整组，⋮ 承载组管理操作。
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    super.key,
    required this.index,
    required this.name,
    required this.memberCount,
  });

  final int index;
  final String name;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ReorderableDelayedDragStartListener(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                ),
                Icon(
                  Icons.folder_outlined,
                  size: 17,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$memberCount 个',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('file-group-menu-$name'),
                  tooltip: '分组管理',
                  icon: const Icon(Icons.more_vert, size: 18),
                  padding: EdgeInsets.zero,
                  onSelected: (value) => _onMenu(context, value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'create', child: Text('在组内新建文件')),
                    PopupMenuItem(value: 'rename', child: Text('重命名分组')),
                    PopupMenuItem(value: 'clear', child: Text('清空分组（删文件）')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'delete', child: Text('删除分组（留文件）')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, String value) async {
    switch (value) {
      case 'create':
        await FileActions.create(context, inGroup: name);
      case 'rename':
        await FileActions.renameGroup(context, name);
      case 'clear':
        await FileActions.clearGroup(context, name);
      case 'delete':
        await FileActions.deleteGroup(context, name);
    }
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({super.key, this.index, required this.file});

  /// 在可拖拽布局中的行下标；null 表示搜索过滤后的扁平列表（不可拖）。
  final int? index;
  final ScoreFile file;

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final theme = Theme.of(context);
    final active = workspace.isActive(file);
    final dirty = workspace.isDirty(file);
    final score = ScoreCalculator.scoreFile(
      file.echoes,
      file.coefficients,
      critThreshold: file.critThreshold,
    );

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            workspace.select(file.id);
            Navigator.of(context).pop();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              children: [
                if (index != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ReorderableDragStartListener(
                      index: index!,
                      child: Icon(
                        Icons.drag_indicator,
                        size: 18,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (dirty)
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        file.hasProfile
                            ? '${Format.scoreWithUnit(score.totalScore)} '
                                  '${Format.rating(score.totalRating)} · ${file.profileName}'
                            : '未选择角色',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (active)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(
                      Icons.check_circle,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                IconButton(
                  tooltip: '复制分享链接',
                  icon: const Icon(Icons.share_outlined, size: 20),
                  onPressed: () =>
                      FileActions.copyShareLink(context, target: file),
                ),
                IconButton(
                  tooltip: '重命名',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => FileActions.rename(context, file),
                ),
                IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => FileActions.delete(context, file),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (index == null) return row;
    return ReorderableDelayedDragStartListener(index: index!, child: row);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching, required this.hasOpen});

  final bool searching;
  final bool hasOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (searching) {
      return _CenteredHint(
        icon: Icons.search_off,
        message: '没有匹配的已打开文件',
        color: theme.colorScheme.onSurfaceVariant,
      );
    }
    if (hasOpen) {
      return _CenteredHint(
        icon: Icons.inbox_outlined,
        message: '没有打开的文件',
        color: theme.colorScheme.onSurfaceVariant,
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.note_add_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              '还没有打开任何评分文件',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => FileActions.create(context),
              icon: const Icon(Icons.add),
              label: const Text('新建评分文件'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => FileActions.open(context),
              child: const Text('打开已有文件'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 34, color: color),
        const SizedBox(height: 10),
        Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('部分数据读取失败'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(child: Text(messages.join('\n'))),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${messages.length} 个文件读取失败',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
