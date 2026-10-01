import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/util/format.dart';
import '../../data/models/echo_entry.dart';
import '../../data/models/score_file.dart';
import '../../domain/score_calculator.dart';
import '../../state/workspace_controller.dart';
import '../detail/echo_detail_page.dart';
import '../widgets/dialogs.dart';
import '../widgets/rating_chip.dart';

/// 总览页里的一件声骸卡片。
///
/// 布局对应需求：第一行名称居中，第二行「当前分数 + 空格 + 评级」，
/// 右上角一个小铅笔图标用于重命名。
class EchoCard extends StatelessWidget {
  const EchoCard({
    required this.file,
    required this.echo,
    required this.score,
    super.key,
  });

  final ScoreFile file;
  final EchoEntry echo;
  final EchoScore score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratingColor = AppPalette.onAccent(
      context,
      AppPalette.rating(score.rating),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: BorderSide(
          color: score.isOverFilled
              ? theme.colorScheme.error
              : ratingColor.withValues(alpha: 0.45),
          width: score.isOverFilled ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => _openDetail(context),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 48, 14),
              child: Column(
                children: [
                  Text(
                    echo.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (score.isOverFilled)
                    Text(
                      '已输入 ${score.filledCount} 条词条，超过 5 条上限',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    ScoreWithRating(
                      key: ValueKey('echo-score-${echo.slot}'),
                      score: score.score,
                      rating: score.rating,
                      scoreFontSize: 24,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    score.isOverFilled
                        ? '请到详情页清除多余词条'
                        : '词条 ${score.filledCount}/${EchoEntry.maxSubstats} · '
                              '理论最高 ${Format.score(score.maxScore)}分 · '
                              '达成 ${(score.ratio * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: '重命名声骸',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 16),
                onPressed: () => _rename(context),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: score.maxScore <= 0 ? 0 : score.ratio.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(ratingColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EchoDetailPage(fileId: file.id, slot: echo.slot),
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final workspace = context.read<WorkspaceController>();
    final name = await Dialogs.promptText(
      context,
      title: '重命名声骸',
      label: '名称',
      initial: echo.name,
      hint: EchoEntry.defaultNameOf(echo.slot),
      confirmLabel: '重命名',
    );
    if (name == null || name == echo.name) return;
    workspace.renameEcho(file.id, echo.slot, name);
    if (context.mounted) {
      Dialogs.snack(context, '已改名，记得保存文件');
    }
  }
}
