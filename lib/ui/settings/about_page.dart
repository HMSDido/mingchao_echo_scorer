import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../data/models/rating.dart';
import '../../state/app_scope.dart';
import '../widgets/dialogs.dart';
import '../widgets/page_header.dart';

/// 「关于」页。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final root = context.read<AppScope>().root.path;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        PageHeader(
          title: AppConstants.appName,
          subtitle: '版本 ${AppConstants.version} · 鸣潮声骸本地评分工具',
        ),
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
                _Line(
                  icon: Icons.wifi_off,
                  text: '完全离线：不联网、不登录、无广告，所有数据只保存在本机。',
                ),
                _Line(icon: Icons.folder_outlined, text: '数据目录：$root'),
                _Line(
                  icon: Icons.swap_horiz,
                  text:
                      '跨设备同步：用「导出为 JSON」把角色系数配置和评分文件带走，'
                      '在另一台设备上导入即可。',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('评分规则', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Card(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line(
                  icon: Icons.functions,
                  text:
                      '单件声骸当前评分 = 13 个词条中所有（非 0 档位数值 × 对应系数）之和，'
                      '取 2 位小数。百分比属性按去掉 % 后的数值计（如 7.5% 记作 7.5）。',
                ),
                _Line(
                  icon: Icons.stacked_line_chart,
                  text: '总分 = 5 件声骸的当前分数之和。',
                ),
                _Line(
                  icon: Icons.workspace_premium_outlined,
                  text:
                      '单件理论最高分 = 13 项「系数 × 该属性最高档位数值」中最大的 5 项之和；'
                      '总理论最高分 = 5 × 单件理论最高分。',
                ),
                _Line(
                  icon: Icons.grade_outlined,
                  text:
                      '评级按「当前分 ÷ 理论最高分」：'
                      '${Rating.values.where((item) => item.isRated).map((item) => '${(item.threshold * 100).toStringAsFixed(0)}% ${item.label}').join('、')}；'
                      '低于 ${(Rating.c.threshold * 100).toStringAsFixed(0)}% 无评级。',
                ),
                _Line(
                  icon: Icons.casino_outlined,
                  text:
                      '达成概率：已输入 i 条词条后，剩下 (5 − i) 条的属性从 '
                      '(13 − i) 个未选属性里等概率不放回抽取，每个属性再按自身档位分布'
                      '独立摇档，求「当前分 + 剩余词条之和 ≥ 目标分」的概率。',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('源代码', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: Text(AppConstants.repositoryUrl),
          onPressed: () => _openRepository(context),
        ),
        const SizedBox(height: 16),
        Text(
          '本应用为玩家自制的第三方工具，与《鸣潮》官方无关。'
          '游戏内的词条数值与概率仅用于本地估算。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Future<void> _openRepository(BuildContext context) async {
    try {
      final launched = await launchUrl(
        Uri.parse(AppConstants.repositoryUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        Dialogs.snack(context, '无法打开浏览器：${AppConstants.repositoryUrl}');
      }
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Icon(icon, size: 16, color: theme.colorScheme.primary),
          ),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
