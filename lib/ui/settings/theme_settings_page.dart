import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/io/transfer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../data/catalog/substat_type.dart';
import '../../data/models/rating.dart';
import '../../state/app_scope.dart';
import '../../state/settings_controller.dart';
import '../widgets/page_header.dart';
import '../widgets/rating_chip.dart';

/// 「主题色设置」页：种子色 + 主题模式 + 自定义背景图 + 配色预览。
class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  /// 选择本地图片并复制进应用私有目录，然后把路径写入设置。
  ///
  /// context 只在第一个 await 之前使用（取好 scope / settings / messenger），
  /// 之后的异步流程不再触碰 context，避免跨异步间隙使用。
  Future<void> _importBackground(BuildContext context) async {
    final scope = context.read<AppScope>();
    final settings = context.read<SettingsController>();
    final messenger = ScaffoldMessenger.of(context);
    final source = await Transfer.pickImage();
    if (source == null) return;
    try {
      final stored = await scope.background.import(
        source,
        previousPath: settings.backgroundImagePath,
      );
      await settings.setBackgroundImagePath(stored);
      messenger.showSnackBar(const SnackBar(content: Text('已设置自定义背景图')));
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('导入背景图失败：$error')));
    }
  }

  /// 清除背景图偏好并删除已复制的图片文件，恢复默认纯色背景。
  Future<void> _restoreDefaultBackground(BuildContext context) async {
    final scope = context.read<AppScope>();
    final settings = context.read<SettingsController>();
    final messenger = ScaffoldMessenger.of(context);
    await scope.background.delete(settings.backgroundImagePath);
    await settings.setBackgroundImagePath(null);
    messenger.showSnackBar(const SnackBar(content: Text('已恢复默认背景')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsController>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        const PageHeader(title: '主题色', subtitle: '界面主色调与明暗模式'),
        const SizedBox(height: 14),
        Text('主题模式', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined),
                label: Text('跟随系统'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('亮色'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('暗色'),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (selection) =>
                settings.setThemeMode(selection.first),
          ),
        ),
        const SizedBox(height: 20),
        Text('主题色', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in AppTheme.seedPresets)
              _Swatch(
                color: color,
                selected: color.toARGB32() == settings.seedColorValue,
                onTap: () => settings.setSeedColor(color),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text('配色预览', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          '评级、副词条属性、档位分别用不同颜色区分，主题色只影响界面主色调，'
          '不会改变这些语义色。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('评级', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final rating in Rating.values.where(
                      (item) => item.isRated,
                    ))
                      RatingChip(rating: rating, fontSize: 14),
                  ],
                ),
                const Divider(height: 26),
                Text('副词条属性', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final type in SubstatType.values)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.attributeSoft(context, type),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppPalette.onAccent(
                              context,
                              AppPalette.attribute(type),
                            ).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          type.label,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppPalette.onAccent(
                              context,
                              AppPalette.attribute(type),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const Divider(height: 26),
                Text('档位', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var tier = 0; tier <= 8; tier++)
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppPalette.tier(tier).withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppPalette.tier(tier)),
                        ),
                        child: Text(
                          '$tier',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.onAccent(
                              context,
                              AppPalette.tier(tier),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('自定义背景图', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          '导入一张本地图片作为整个应用的背景。图片会复制进应用私有目录，'
          '并压上一层半透明遮罩，保证文字与按钮依然清晰。'
          '支持 jpg / jpeg / png / webp。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _BackgroundCard(
          path: settings.backgroundImagePath,
          onImport: () => _importBackground(context),
          onRestore: () => _restoreDefaultBackground(context),
        ),
      ],
    );
  }
}

/// 「自定义背景图」卡片：预览缩略图 + 当前状态 + 导入 / 恢复默认两个按钮。
class _BackgroundCard extends StatelessWidget {
  const _BackgroundCard({
    required this.path,
    required this.onImport,
    required this.onRestore,
  });

  final String? path;
  final VoidCallback onImport;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBackground = path?.trim().isNotEmpty ?? false;
    return Card(
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
                _BackgroundPreview(path: path),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasBackground ? '当前：自定义背景' : '当前：默认背景',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasBackground
                            ? '背景图已复制进应用私有目录，重启后依旧生效。'
                            : '尚未导入背景图，使用主题纯色背景。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('导入图片'),
                  onPressed: onImport,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.restore),
                  label: const Text('恢复默认背景'),
                  onPressed: hasBackground ? onRestore : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 背景图预览缩略图；无背景时显示占位图标。
class _BackgroundPreview extends StatelessWidget {
  const _BackgroundPreview({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = path?.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 96,
        height: 60,
        alignment: Alignment.center,
        color: theme.colorScheme.surfaceContainerHighest,
        child: value.isEmpty
            ? Icon(Icons.wallpaper_outlined, color: theme.colorScheme.outline)
            : Image.file(
                File(value),
                width: 96,
                height: 60,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: 240,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.broken_image_outlined,
                  color: theme.colorScheme.outline,
                ),
              ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: selected ? '当前主题色' : '使用这个颜色',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 3,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : null,
        ),
      ),
    );
  }
}
