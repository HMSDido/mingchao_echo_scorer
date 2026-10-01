import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/util/format.dart';
import '../../data/models/score_file.dart';
import '../../domain/score_calculator.dart';
import '../../state/workspace_controller.dart';
import '../actions/file_actions.dart';

/// 左侧文件栏：已打开的评分文件列表 + 文件名搜索。
class FilePanel extends StatefulWidget {
  const FilePanel({super.key});

  @override
  State<FilePanel> createState() => _FilePanelState();
}

class _FilePanelState extends State<FilePanel> {
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
    final theme = Theme.of(context);
    final files = workspace.visibleOpenFiles;
    // 外部（例如快捷键）清空了搜索词时同步输入框。
    if (_search.text != workspace.fileQuery) {
      _search
        ..text = workspace.fileQuery
        ..selection = TextSelection.collapsed(
          offset: workspace.fileQuery.length,
        );
    }

    return SizedBox(
      width: AppConstants.filePanelWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '评分文件',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '新建文件',
                  icon: const Icon(Icons.note_add_outlined),
                  onPressed: () => FileActions.create(context),
                ),
                IconButton(
                  tooltip: '打开文件',
                  icon: const Icon(Icons.folder_open),
                  onPressed: () => FileActions.open(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: '搜索文件名',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: workspace.fileQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _clearSearch,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: files.isEmpty
                ? _EmptyHint(
                    searching: workspace.fileQuery.trim().isNotEmpty,
                    hasOpen: workspace.openFiles.isNotEmpty,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    itemCount: files.length,
                    itemBuilder: (context, index) =>
                        _FileTile(file: files[index]),
                  ),
          ),
          if (workspace.diskErrors.isNotEmpty)
            _ErrorBanner(messages: workspace.diskErrors),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file});

  final ScoreFile file;

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final theme = Theme.of(context);
    final active = workspace.isActive(file);
    final dirty = workspace.isDirty(file);
    final score = ScoreCalculator.scoreFile(file.echoes, file.coefficients);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => workspace.select(file.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (dirty) ...[
                            Tooltip(
                              message: '有未保存的改动',
                              child: Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                          Expanded(
                            child: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
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
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  icon: const Icon(Icons.more_vert, size: 18),
                  padding: EdgeInsets.zero,
                  onSelected: (value) => _onMenu(context, value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'save', child: Text('保存')),
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'export', child: Text('导出为 JSON')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'close', child: Text('关闭文件')),
                    PopupMenuItem(value: 'delete', child: Text('删除文件')),
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
      case 'save':
        await FileActions.save(context, target: file);
      case 'rename':
        await FileActions.rename(context, file);
      case 'export':
        await FileActions.export(context, target: file);
      case 'close':
        await FileActions.close(context, file);
      case 'delete':
        await FileActions.delete(context, file);
    }
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.searching, required this.hasOpen});

  final bool searching;
  final bool hasOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, message) = switch ((searching, hasOpen)) {
      (true, _) => (Icons.search_off, '没有匹配的已打开文件'),
      (false, true) => (Icons.inbox_outlined, '没有打开的文件'),
      (false, false) => (
        Icons.note_add_outlined,
        '还没有打开任何评分文件\n点上方 + 新建，或打开已有文件',
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: theme.colorScheme.outline),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
