import 'package:flutter/material.dart';

import '../../core/theme/palette.dart';
import '../../data/models/rating.dart';

/// 评级徽章：字母 + 等级色。
class RatingChip extends StatelessWidget {
  const RatingChip({required this.rating, this.fontSize = 13, super.key});

  final Rating rating;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final color = AppPalette.onAccent(context, AppPalette.rating(rating));
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        rating.isRated ? rating.label : '—',
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          height: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// `66.66分 S级`：分数与评级同处一行，评级带颜色。
class ScoreWithRating extends StatelessWidget {
  const ScoreWithRating({
    required this.score,
    required this.rating,
    this.scoreFontSize = 20,
    this.unitFontSize,
    super.key,
  });

  final double score;
  final Rating rating;
  final double scoreFontSize;
  final double? unitFontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unitSize = unitFontSize ?? scoreFontSize * 0.55;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: score.toStringAsFixed(2),
            style: TextStyle(
              fontSize: scoreFontSize,
              fontWeight: FontWeight.w700,
              height: 1.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(
            text: '分 ',
            style: TextStyle(fontSize: unitSize, fontWeight: FontWeight.w500),
          ),
          TextSpan(
            text: rating.isRated ? '${rating.label}级' : '无评级',
            style: TextStyle(
              fontSize: scoreFontSize * 0.85,
              fontWeight: FontWeight.w700,
              color: AppPalette.onAccent(context, AppPalette.rating(rating)),
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyLarge,
    );
  }
}
