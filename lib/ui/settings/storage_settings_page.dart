import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/io/transfer.dart';
import '../../state/app_scope.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace_controller.dart';
import '../widgets/dialogs.dart';
import '../widgets/page_header.dart';

/// 「文件存储位置设置」页。
///
/// Windows 允许自由选择目录；Android 受作用域存储限制，只能用应用私有目录，
/// 跨设备同步靠剪贴板分享链接。
class StorageSettingsPage extends StatelessWidget {
  const StorageSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = context.read<AppScope>();
    final settings = context.watch<SettingsController>();
    final isCustom = settings.customStorageRoot != null;
    final path = scope.root.path;
    final canChoose = !Platform.isAndroid;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        const PageHeader(title: '文件存储位置', subtitle: '评分文件与角色系数配置都保存在这个目录下'),
        const SizedBox(height: 14),
        Card(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isCustom ? Icons.folder_special : Icons.folder_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isCustom ? '自定义位置' : '默认位置',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  path,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canChoose)
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.drive_file_move_outlined),
                        label: const Text('选择文件夹…'),
                        onPressed: () => _choose(context),
                      ),
                    IconButton.filledTonal(
                      tooltip: '复制路径',
                      icon: const Icon(Icons.copy_all_outlined),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: path));
                        if (context.mounted) {
                          Dialogs.snack(context, '路径已复制到剪贴板');
                        }
                      },
                    ),
                    if (isCustom)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.settings_backup_restore),
                        label: const Text('恢复默认位置'),
                        onPressed: () => _apply(context, null),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('目录结构', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        _StructureLine(name: 'profiles/', description: '角色系数配置，每个配置一个 JSON'),
        _StructureLine(
          name: 'scores/<文件名>/',
          description: '每个评分文件一个自命名文件夹，内含 score.json',
        ),
        const SizedBox(height: 16),
        Text(
          canChoose
              ? '切换目录后，当前打开的文件会先关闭（有未保存改动的请先保存）。'
                    '原目录里的数据不会被移动或删除，切回去即可继续使用。'
              : 'Android 上应用只能读写自己的私有目录，因此位置固定。'
                    '需要换设备时用「复制链接」把分享链接带走，'
                    '在另一台设备上「粘贴导入」即可。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _choose(BuildContext context) async {
    try {
      final picked = await Transfer.pickDirectory(dialogTitle: '选择数据存储目录');
      if (picked == null || !context.mounted) return;
      await _apply(context, picked);
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }

  Future<void> _apply(BuildContext context, String? path) async {
    final scope = context.read<AppScope>();
    final workspace = context.read<WorkspaceController>();
    final dirty = workspace.dirtyFiles;

    final message = StringBuffer();
    if (dirty.isNotEmpty) {
      message.write(
        '以下文件还有未保存的改动，切换位置会丢失这些改动：'
        '${dirty.map((file) => file.name).join('、')}。\n\n',
      );
    }
    message.write(path == null ? '确定恢复到默认存储位置吗？' : '确定把存储位置切换到\n$path\n吗？');

    final ok = await Dialogs.confirm(
      context,
      title: '切换存储位置',
      message: message.toString(),
      confirmLabel: '切换',
      destructive: dirty.isNotEmpty,
    );
    if (!ok || !context.mounted) return;

    try {
      await scope.changeStorageRoot(path);
      if (context.mounted) {
        Dialogs.snack(context, '存储位置已切换到 ${scope.root.path}');
      }
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }
}

class _StructureLine extends StatelessWidget {
  const _StructureLine({required this.name, required this.description});

  final String name;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              name,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
