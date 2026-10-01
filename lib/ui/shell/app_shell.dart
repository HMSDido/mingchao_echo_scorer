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
            appBar: AppBar(
              title: const Text(AppConstants.appName),
              titleSpacing: 0,
            ),
            drawer: Drawer(
              child: SafeArea(
                child: Column(
                  children: const [
                    Expanded(
                      flex: 3,
                      child: NavRail(variant: NavRailVariant.drawer),
                    ),
                    Divider(height: 1),
                    Expanded(flex: 4, child: FilePanel()),
                  ],
                ),
              ),
            ),
            body: body,
          );

    return AppBackground(imagePath: backgroundPath, child: scaffold);
  }

  Widget _content(BuildContext context, bool wide) {
    if (!wide) {
      return const Column(
        children: [
          TopToolbar(compact: true),
          Divider(height: 1),
          Expanded(child: _MainArea()),
        ],
      );
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
