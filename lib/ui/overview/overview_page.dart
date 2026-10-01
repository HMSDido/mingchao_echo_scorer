import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/util/format.dart';
import '../../data/models/echo_entry.dart';
import '../../data/models/score_file.dart';
import '../../domain/score_calculator.dart';
import '../../state/workspace_controller.dart';
import '../actions/file_actions.dart';
import '../widgets/rating_chip.dart';
import 'echo_card.dart';

/// 主界面的总分总览页。
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  static const double _maxContentWidth = 620;

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final file = workspace.activeFile;
    if (file == null) return const _NoFileView();

    final score = ScoreCalculator.scoreFile(file.echoes, file.coefficients);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            if (!file.hasProfile) _ProfilePrompt(file: file),
            if (file.hasProfile) ...[
              _TotalScore(file: file, score: score),
              const SizedBox(height: 18),
            ],
            for (var slot = 0; slot < EchoEntry.slotCount; slot++) ...[
              EchoCard(
                file: file,
                echo: file.echoAt(slot),
                score: score.echoes[slot],
              ),
              if (slot != EchoEntry.slotCount - 1) const SizedBox(height: 10),
            ],
            const SizedBox(height: 18),
            _FileFooter(file: file, score: score),
          ],
        ),
      ),
    );
  }
}

class _NoFileView extends StatelessWidget {
  const _NoFileView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.summarize_outlined,
              size: 52,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 14),
            Text('还没有打开评分文件', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '新建一个文件开始评分，或打开磁盘上已有的文件。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('新建文件'),
                  onPressed: () => FileActions.create(context),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('打开文件'),
                  onPressed: () => FileActions.open(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfilePrompt extends StatelessWidget {
  const _ProfilePrompt({required this.file});

  final ScoreFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: theme.colorScheme.tertiaryContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(
              Icons.person_search_outlined,
              size: 34,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(height: 10),
            Text(
              '「${file.name}」还没有选择角色',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '评分公式需要 13 项词条系数。选择一份已保存的角色系数配置，'
              '它的系数会被代入本文件的公式。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              icon: const Icon(Icons.assignment_ind_outlined),
              label: const Text('选择角色'),
              onPressed: () => FileActions.chooseProfile(context, file),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部正中：总分 + 总评级，数字与字母放大加粗。
class _TotalScore extends StatelessWidget {
  const _TotalScore({required this.file, required this.score});

  final ScoreFile file;
  final FileScore score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratingColor = AppPalette.onAccent(
      context,
      AppPalette.rating(score.totalRating),
    );

    return Column(
      children: [
        Text(
          file.hasProfile ? '角色：${file.profileName}' : '总分',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: Format.score(score.totalScore),
                style: const TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              TextSpan(
                text: '分 ',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              TextSpan(
                text: score.totalRating.isRated
                    ? '${score.totalRating.label}级'
                    : '无评级',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  color: ratingColor,
                ),
              ),
            ],
          ),
          key: const ValueKey('total-score'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          '理论最高 ${Format.score(score.totalMaxScore)}分 · '
          '达成 ${(score.ratio * 100).toStringAsFixed(1)}%',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Center(child: RatingChip(rating: score.totalRating, fontSize: 15)),
      ],
    );
  }
}

class _FileFooter extends StatelessWidget {
  const _FileFooter({required this.file, required this.score});

  final ScoreFile file;
  final FileScore score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workspace = context.watch<WorkspaceController>();
    final overFilled = score.echoes.where((item) => item.isOverFilled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (overFilled > 0)
          Card(
            color: theme.colorScheme.errorContainer,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '有 $overFilled 件声骸的词条超过 5 条，不计入总分。'
                      '进入详情页清除多余词条后即可正常评分。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.swap_horiz),
              label: Text(file.hasProfile ? '更换角色' : '选择角色'),
              onPressed: () => FileActions.chooseProfile(context, file),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存'),
              onPressed: () => FileActions.save(context, target: file),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('导出'),
              onPressed: () => FileActions.export(context, target: file),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.drive_file_rename_outline),
              label: const Text('重命名'),
              onPressed: () => FileActions.rename(context, file),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          workspace.isDirty(file)
              ? '有未保存的改动 · 最近保存于 ${Format.dateTime(file.updatedAt)}'
              : '已保存 · ${Format.dateTime(file.updatedAt)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
