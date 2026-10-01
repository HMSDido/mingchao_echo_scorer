import 'package:flutter/material.dart';

import '../../core/theme/palette.dart';
import '../../core/util/format.dart';
import '../../data/models/echo_entry.dart';
import '../../data/models/rating.dart';
import '../../domain/expected_max_calculator.dart';
import '../../domain/probability_calculator.dart';
import '../../domain/score_calculator.dart';
import '../widgets/rating_chip.dart';

/// 详情页右侧（窄屏时下方）的输出区：当前评分、预期最高分、目标分与达成概率。
///
/// 目标分输入框与达成概率显示在同一块区域内。
class OutputPanel extends StatelessWidget {
  const OutputPanel({
    required this.score,
    required this.expectedMax,
    required this.probability,
    required this.targetController,
    required this.onTargetChanged,
    required this.overFilled,
    super.key,
  });

  final EchoScore score;
  final ExpectedMax? expectedMax;
  final ProbabilityOutcome? probability;
  final TextEditingController targetController;
  final ValueChanged<String> onTargetChanged;

  /// 非 0 档位词条超过 5 条：按需求不输出任何结果，只给提示。
  final bool overFilled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (overFilled) {
      return Card(
        color: theme.colorScheme.errorContainer,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.block, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '已选择 ${score.filledCount} 条词条，超过 '
                  '${EchoEntry.maxSubstats} 条上限，因此不输出评分结果。\n'
                  '请把多余的词条改回「0档 · 未开出」。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final expected = expectedMax;
    return Card(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(index: '①', text: '当前评分'),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: ScoreWithRating(
                key: const ValueKey('current-score'),
                score: score.score,
                rating: score.rating,
                scoreFontSize: 30,
              ),
            ),
            Text(
              '词条 ${score.filledCount}/${EchoEntry.maxSubstats} · '
              '理论最高 ${Format.score(score.maxScore)}分 · '
              '达成 ${(score.ratio * 100).toStringAsFixed(1)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 26),
            _SectionTitle(index: '②', text: '预期最高分'),
            const SizedBox(height: 4),
            Text(
              expected == null
                  ? '—'
                  : '${Format.scoreWithUnit(expected.value)} '
                        '${Format.rating(Rating.fromScore(expected.value, score.maxScore))}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (expected != null)
              Text(
                expected.remainingSlots == 0
                    ? '5 条词条已开满，没有剩余槽位。'
                    : '剩余 ${expected.remainingSlots} 条若都开在最优属性上：'
                          '${expected.bestRemaining.map((t) => t.label).join('、')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const Divider(height: 26),
            _SectionTitle(index: '③', text: '目标分数与达成概率'),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: const ValueKey('target-score-input'),
                    controller: targetController,
                    onChanged: onTargetChanged,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '目标分数',
                      hintText: '如 80.00',
                      suffixText: '分',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: _ProbabilityView(outcome: probability)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '概率含义：剩下 ${expected?.remainingSlots ?? 0} 条词条的属性与档位都是随机的，'
              '「当前分 + 剩余词条之和 ≥ 目标分」的可能性。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.index, required this.text});

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          index,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ProbabilityView extends StatelessWidget {
  const _ProbabilityView({required this.outcome});

  final ProbabilityOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = outcome;
    if (result == null) {
      return Text(
        '填入目标分数后显示达成概率',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    }

    // 概率越高越接近达标色带里的暖色，便于一眼看出希望大小。
    final tier = (result.probability * 8).round().clamp(0, 8);
    final color = AppPalette.onAccent(context, AppPalette.tier(tier));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Format.percent(result.probability),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.1,
          ),
        ),
        Text(
          result.approximate ? '达成概率（近似值）' : '达成概率',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
