import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/util/format.dart';
import '../../data/catalog/substat_type.dart';
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

    final score = ScoreCalculator.scoreFile(
      file.echoes,
      file.coefficients,
      critThreshold: file.critThreshold,
    );

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
              _CritPanel(
                key: ValueKey('crit-panel-${file.id}'),
                file: file,
                score: score,
              ),
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

/// 副词条合计 + 暴击率阈值面板。
///
/// 合计是 5 件声骸各属性档位数值之和（派生输出）；阈值是选填输入，随文件落盘，
/// 合计超出阈值时顶部给出提醒，且超出部分已在总分里扣除。
class _CritPanel extends StatefulWidget {
  const _CritPanel({super.key, required this.file, required this.score});

  final ScoreFile file;
  final FileScore score;

  @override
  State<_CritPanel> createState() => _CritPanelState();
}

class _CritPanelState extends State<_CritPanel> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.file.critThreshold?.toStringAsFixed(1) ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    final workspace = context.read<WorkspaceController>();
    final cleaned = text.replaceAll('%', '').trim();
    if (cleaned.isEmpty) {
      if (widget.file.critThreshold != null) {
        workspace.updateFile(widget.file.copyWith(clearCritThreshold: true));
      }
      return;
    }
    final parsed = double.tryParse(cleaned);
    if (parsed == null || !parsed.isFinite || parsed < 0) return;
    if (widget.file.critThreshold != parsed) {
      workspace.updateFile(widget.file.copyWith(critThreshold: parsed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = widget.score;
    final filled = SubstatType.values
        .where((type) => score.substatTotals[type]! > 0)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (score.hasCritOverflow) ...[
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
                      '暴击率合计 ${SubstatType.critRate.displaySumOf(score.critSum)}'
                      ' 已超过阈值 '
                      '${SubstatType.critRate.displaySumOf(score.critThreshold!)}，'
                      '超出的 '
                      '${SubstatType.critRate.displaySumOf(score.critExcess)}'
                      ' 不计入总分。',
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
        ],
        Card(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('副词条合计（5 件声骸）', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                if (filled.isEmpty)
                  Text(
                    '还没有录入任何词条。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in filled)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${type.label} '
                            '${type.displaySumOf(score.substatTotals[type]!)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('crit-threshold'),
                  controller: _controller,
                  onChanged: _onChanged,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.%]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: '当前角色暴击阈值（选填）',
                    hintText: 'XX.X%',
                    suffixText: '%',
                    helperText: '暴击率合计超过该值时，超出部分不计入总分',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
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
