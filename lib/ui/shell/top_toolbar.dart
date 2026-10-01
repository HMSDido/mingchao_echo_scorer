import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/util/format.dart';
import '../../data/models/score_file.dart';
import '../../domain/score_calculator.dart';
import '../../state/workspace_controller.dart';
import '../actions/file_actions.dart';

/// 主区域顶部的功能键栏：新建、打开、保存、导入、导出。
class TopToolbar extends StatelessWidget {
  const TopToolbar({this.compact = false, super.key});

  /// 窄屏下只显示图标。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final theme = Theme.of(context);
    final file = workspace.activeFile;
    final hasFile = file != null;
    final dirty = hasFile && workspace.isDirty(file);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _ToolbarButton(
                icon: Icons.note_add_outlined,
                label: '新建',
                compact: compact,
                onPressed: () => FileActions.create(context),
              ),
              _ToolbarButton(
                icon: Icons.folder_open,
                label: '打开',
                compact: compact,
                onPressed: () => FileActions.open(context),
              ),
              const _Separator(),
              _ToolbarButton(
                icon: dirty ? Icons.save : Icons.save_outlined,
                label: '保存',
                compact: compact,
                highlighted: dirty,
                onPressed: hasFile ? () => FileActions.save(context) : null,
              ),
              _ToolbarButton(
                icon: Icons.file_download_outlined,
                label: '导入',
                compact: compact,
                onPressed: () => FileActions.importFile(context),
              ),
              _ToolbarButton(
                icon: Icons.file_upload_outlined,
                label: '导出',
                compact: compact,
                onPressed: hasFile ? () => FileActions.export(context) : null,
              ),
              const Spacer(),
              if (hasFile) _FileStatus(file: file, dirty: dirty),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.compact,
    required this.onPressed,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback? onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = onPressed == null
        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : highlighted
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: compact
          ? IconButton(
              tooltip: label,
              icon: Icon(icon, color: foreground),
              onPressed: onPressed,
            )
          : Tooltip(
              message: label,
              child: TextButton.icon(
                icon: Icon(icon, size: 18, color: foreground),
                label: Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                onPressed: onPressed,
              ),
            ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

class _FileStatus extends StatelessWidget {
  const _FileStatus({required this.file, required this.dirty});

  final ScoreFile file;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = ScoreCalculator.scoreFile(file.echoes, file.coefficients);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${Format.scoreWithUnit(score.totalScore)} '
          '${Format.rating(score.totalRating)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: dirty ? '有未保存的改动' : '已保存',
          child: Icon(
            dirty ? Icons.circle : Icons.check_circle_outline,
            size: 12,
            color: dirty ? theme.colorScheme.error : theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
