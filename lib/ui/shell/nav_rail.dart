import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace_controller.dart';
import '../widgets/dialogs.dart';

/// 导航栏的两种形态：宽屏时的可伸缩竖栏，窄屏抽屉里的整宽列表。
enum NavRailVariant { rail, drawer }

/// 最左侧的设置导航栏。
class NavRail extends StatelessWidget {
  const NavRail({this.variant = NavRailVariant.rail, super.key});

  final NavRailVariant variant;

  static const List<_NavItem> _views = [
    _NavItem(ShellView.files, '评分文件', Icons.folder_open),
    _NavItem(ShellView.profiles, '编辑角色系数', Icons.tune),
    _NavItem(ShellView.settings, '系统设置', Icons.settings),
    _NavItem(ShellView.storage, '文件存储位置', Icons.folder_copy_outlined),
    _NavItem(ShellView.theme, '主题色', Icons.palette_outlined),
    _NavItem(ShellView.about, '关于', Icons.info_outline),
  ];

  /// 导航项的中文标题，供窄屏顶栏复用。
  static String labelOf(ShellView view) =>
      _views.firstWhere((item) => item.view == view).label;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final workspace = context.watch<WorkspaceController>();
    final expanded = variant == NavRailVariant.drawer || settings.navExpanded;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(expanded: expanded),
        const SizedBox(height: 8),
        for (final item in _views)
          _NavButton(
            icon: item.icon,
            label: item.label,
            expanded: expanded,
            selected: workspace.view == item.view,
            onTap: () => _select(context, item.view),
          ),
        _NavButton(
          icon: Icons.open_in_new,
          label: 'GitHub 仓库',
          expanded: expanded,
          selected: false,
          onTap: () => _openRepository(context),
        ),
        const Spacer(),
        if (variant == NavRailVariant.rail)
          _NavButton(
            icon: expanded
                ? Icons.keyboard_double_arrow_left
                : Icons.keyboard_double_arrow_right,
            label: expanded ? '收起导航栏' : '展开导航栏',
            expanded: expanded,
            selected: false,
            onTap: settings.toggleNavExpanded,
          ),
        const SizedBox(height: 8),
      ],
    );

    if (variant == NavRailVariant.drawer) return content;
    return SizedBox(
      width: expanded
          ? AppConstants.navRailExpandedWidth
          : AppConstants.navRailCollapsedWidth,
      child: content,
    );
  }

  void _select(BuildContext context, ShellView view) {
    context.read<WorkspaceController>().show(view);
    if (variant == NavRailVariant.drawer) Navigator.of(context).maybePop();
  }

  Future<void> _openRepository(BuildContext context) async {
    final uri = Uri.parse(AppConstants.repositoryUrl);
    try {
      final launched = await launchUrl(
        uri,
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

class _NavItem {
  const _NavItem(this.view, this.label, this.icon);

  final ShellView view;
  final String label;
  final IconData icon;
}

class _Header extends StatelessWidget {
  const _Header({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 18,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          if (expanded) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppConstants.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final button = Material(
      color: selected
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(icon, size: 20, color: foreground),
              if (expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: expanded ? button : Tooltip(message: label, child: button),
    );
  }
}
