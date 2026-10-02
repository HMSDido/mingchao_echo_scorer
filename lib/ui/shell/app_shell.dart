import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace_controller.dart';
import '../actions/file_actions.dart';
import '../overview/overview_page.dart';
import '../profiles/profile_list_page.dart';
import '../settings/about_page.dart';
import '../settings/settings_page.dart';
import '../settings/storage_settings_page.dart';
import '../settings/theme_settings_page.dart';
import '../widgets/app_background.dart';
import '../widgets/dialogs.dart';
import 'file_list_page.dart';
import 'file_panel.dart';
import 'nav_rail.dart';
import 'top_toolbar.dart';

/// 应用外壳：最左导航栏 + 文件栏 + 顶部功能键栏 + 主输入输出区。
///
/// [windowCloseGuard] 为 true 时（Windows 桌面）拦截窗口关闭，先处理未保存改动。
class AppShell extends StatefulWidget {
  const AppShell({this.windowCloseGuard = false, super.key});

  final bool windowCloseGuard;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (widget.windowCloseGuard) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (widget.windowCloseGuard) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (!widget.windowCloseGuard) return;
    _confirmAndClose();
  }

  Future<void> _confirmAndClose() async {
    if (!await windowManager.isPreventClose()) {
      await windowManager.destroy();
      return;
    }
    if (!mounted) return;
    final workspace = context.read<WorkspaceController>();

    // 声骸详情页可能还压着未保存的草稿，先让它自己询问。
    if (!await workspace.runGuards()) return;
    if (!mounted) return;

    if (workspace.hasUnsavedChanges) {
      final names = workspace.dirtyFiles.map((file) => file.name).join('、');
      final choice = await Dialogs.promptUnsaved(
        context,
        title: '有未保存的改动',
        message: '以下文件尚未保存：$names。\n退出前要保存吗？',
      );
      if (choice == UnsavedChoice.cancel || !mounted) return;
      if (choice == UnsavedChoice.save) await workspace.saveAll();
    }
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final backgroundPath = context.select<SettingsController, String?>(
      (settings) => settings.backgroundImagePath,
    );
    final wide =
        MediaQuery.sizeOf(context).width >= AppConstants.compactWidthBreakpoint;

    final body = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (workspace.view == ShellView.files) FileActions.save(context);
        },
      },
      child: Focus(autofocus: true, child: _content(context, wide)),
    );

    // 有自定义背景图时让 Scaffold 透明，背景层（图片 + 遮罩）才能透出来；
    // 侧边栏、文件栏、工具栏与卡片仍是不透明表面，可读性不受影响。
    final hasBackground = backgroundPath?.trim().isNotEmpty ?? false;
    final backgroundColor = hasBackground ? Colors.transparent : null;

    final scaffold = wide
        ? Scaffold(backgroundColor: backgroundColor, body: body)
        : Scaffold(
            backgroundColor: backgroundColor,
            appBar: const _NarrowAppBar(),
            drawer: const Drawer(
              child: SafeArea(child: NavRail(variant: NavRailVariant.drawer)),
            ),
            body: body,
          );

    return AppBackground(imagePath: backgroundPath, child: scaffold);
  }

  Widget _content(BuildContext context, bool wide) {
    if (!wide) {
      // 窄屏的功能键全部收进顶栏（见 _NarrowAppBar），正文只留当前页。
      return const _MainArea();
    }
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: theme.colorScheme.surfaceContainerLowest,
          child: const NavRail(),
        ),
        const VerticalDivider(width: 1),
        ColoredBox(
          color: theme.colorScheme.surfaceContainerLow,
          child: const FilePanel(),
        ),
        const VerticalDivider(width: 1),
        const Expanded(
          child: Column(
            children: [
              TopToolbar(),
              Divider(height: 1),
              Expanded(child: _MainArea()),
            ],
          ),
        ),
      ],
    );
  }
}

/// 主区域：按导航选择切换页面。
class _MainArea extends StatelessWidget {
  const _MainArea();

  @override
  Widget build(BuildContext context) {
    final view = context.select<WorkspaceController, ShellView>(
      (workspace) => workspace.view,
    );
    final loading = context.select<WorkspaceController, bool>(
      (workspace) => workspace.loading,
    );
    if (loading) return const Center(child: CircularProgressIndicator());

    return switch (view) {
      ShellView.files => const OverviewPage(),
      ShellView.profiles => const ProfileListPage(),
      ShellView.settings => const SettingsPage(),
      ShellView.storage => const StorageSettingsPage(),
      ShellView.theme => const ThemeSettingsPage(),
      ShellView.about => const AboutPage(),
    };
  }
}

/// 窄屏顶栏：汉堡菜单 + 当前页/当前文件标题 + 少量图标 + ⋮ 溢出菜单。
///
/// 只有「评分文件」页需要文件级操作；其余页面各自的页头已经够用，这里不再堆按钮。
class _NarrowAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _NarrowAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  void _openTabs(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const FileListPage()));
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final theme = Theme.of(context);
    final onFiles = workspace.view == ShellView.files;
    final file = onFiles ? workspace.activeFile : null;
    final dirty = file != null && workspace.isDirty(file);

    return AppBar(
      titleSpacing: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              file?.name ??
                  (onFiles
                      ? AppConstants.appName
                      : NavRail.labelOf(workspace.view)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (dirty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Tooltip(
                message: '有未保存的改动',
                child: Icon(
                  Icons.circle,
                  size: 9,
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      actions: !onFiles
          ? null
          : [
              IconButton(
                tooltip: '标签页',
                icon: const Icon(Icons.tab),
                onPressed: () => _openTabs(context),
              ),
              if (file != null)
                IconButton(
                  tooltip: '保存',
                  icon: Icon(dirty ? Icons.save : Icons.save_outlined),
                  onPressed: () => FileActions.save(context, target: file),
                ),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (value) {
                  final target = file;
                  switch (value) {
                    case 'create':
                      FileActions.create(context);
                    case 'open':
                      FileActions.open(context);
                    case 'import':
                      FileActions.importFromClipboard(context);
                    case 'deleteMany':
                      FileActions.deleteMany(context);
                    case 'copy':
                      FileActions.copyShareLink(context);
                    case 'rename':
                      if (target != null) FileActions.rename(context, target);
                    case 'profile':
                      if (target != null) {
                        FileActions.chooseProfile(context, target);
                      }
                    case 'close':
                      if (target != null) FileActions.close(context, target);
                    case 'delete':
                      if (target != null) FileActions.delete(context, target);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'create', child: Text('新建评分文件')),
                  const PopupMenuItem(value: 'open', child: Text('打开已有文件')),
                  const PopupMenuItem(value: 'import', child: Text('粘贴导入')),
                  const PopupMenuItem(value: 'deleteMany', child: Text('批量删除')),
                  if (file != null) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'copy', child: Text('复制分享链接')),
                    const PopupMenuItem(value: 'rename', child: Text('重命名')),
                    const PopupMenuItem(
                      value: 'profile',
                      child: Text('选择角色系数'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'close', child: Text('关闭文件')),
                    const PopupMenuItem(value: 'delete', child: Text('删除文件')),
                  ],
                ],
              ),
            ],
    );
  }
}
