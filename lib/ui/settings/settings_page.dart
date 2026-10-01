import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';
import '../../state/workspace_controller.dart';
import '../widgets/page_header.dart';

/// 「系统设置」页：外观与数据相关的入口汇总。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsController>();
    final workspace = context.read<WorkspaceController>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        const PageHeader(title: '系统设置', subtitle: '外观、数据存储位置与应用信息'),
        const SizedBox(height: 12),
        Card(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: const Text('主题模式'),
                  subtitle: const Text('亮色 / 暗色 / 跟随系统'),
                  trailing: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('系统')),
                      ButtonSegment(value: ThemeMode.light, label: Text('亮')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('暗')),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (selection) =>
                        settings.setThemeMode(selection.first),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('主题色'),
                  subtitle: const Text('界面主色调'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => workspace.show(ShellView.theme),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.folder_copy_outlined),
                  title: const Text('文件存储位置'),
                  subtitle: const Text('评分文件与角色系数配置的保存目录'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => workspace.show(ShellView.storage),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于'),
                  subtitle: const Text('版本、离线说明与 GitHub 仓库'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => workspace.show(ShellView.about),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '本应用完全离线运行：不联网、不登录，全部数据只保存在本机。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
