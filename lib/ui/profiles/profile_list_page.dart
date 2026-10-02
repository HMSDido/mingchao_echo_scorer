import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/util/format.dart';
import '../../data/models/coefficient_profile.dart';
import '../../domain/score_calculator.dart';
import '../../state/profile_controller.dart';
import '../actions/profile_actions.dart';
import '../widgets/dialogs.dart';
import '../../state/library_layout.dart';

/// 「编辑角色系数」页：可分组、可拖拽的配置列表 + 新建按钮 + ⋮ 菜单。
///
/// 列表用 [ReorderableListView]：组标题也是可拖的行，拖标题整组移动，
/// 拖条目即可跨组 / 跨根层移动；宽窄屏共用这一份实现。
class ProfileListPage extends StatefulWidget {
  const ProfileListPage({super.key});

  @override
  State<ProfileListPage> createState() => _ProfileListPageState();
}

class _ProfileListPageState extends State<ProfileListPage> {
  @override
  void initState() {
    super.initState();
    // 每次进入都刷新，保证别的入口（导入、编辑器保存）的结果立即可见。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProfileController>().reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProfileController>();
    final theme = Theme.of(context);
    final rows = controller.layoutRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '角色系数配置',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '13 项副词条的权重，评分文件选定后会把它作为快照代入公式',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: const ValueKey('profiles-menu'),
                tooltip: '更多操作',
                onSelected: (value) {
                  switch (value) {
                    case 'newGroup':
                      ProfileActions.addGroup(context);
                    case 'import':
                      ProfileActions.importFromClipboard(context);
                    case 'copyAll':
                      ProfileActions.copyToClipboard(
                        context,
                        context.read<ProfileController>().profiles,
                      );
                    case 'deleteMany':
                      ProfileActions.deleteMany(context);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'newGroup', child: Text('新建分组')),
                  PopupMenuItem(value: 'import', child: Text('从剪贴板导入配置')),
                  PopupMenuItem(value: 'copyAll', child: Text('复制全部配置到剪贴板')),
                  PopupMenuItem(value: 'deleteMany', child: Text('批量删除')),
                ],
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('新建配置'),
                onPressed: () => ProfileActions.create(context),
              ),
            ],
          ),
        ),
        const _ShareBanner(),
        if (rows.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune,
                      size: 46,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text('还没有角色系数配置', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(
                      '新建一份配置，逐项填入 13 个副词条的系数。\n'
                      '也可以复制别人分享的内容，再点右上 ⋮ →「从剪贴板导入配置」。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              buildDefaultDragHandles: false,
              itemCount: rows.length,
              onReorderItem: (oldIndex, newIndex) =>
                  controller.moveLayoutRow(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final row = rows[index];
                if (row.isGroup) {
                  return _GroupTile(
                    key: ValueKey('g:${row.value}'),
                    index: index,
                    name: row.value,
                    memberCount: _groupSize(rows, index),
                  );
                }
                final profile = controller.byId(row.value);
                if (profile == null) {
                  return SizedBox.shrink(key: ValueKey('ghost-$index'));
                }
                return _ProfileTile(
                  key: ValueKey('p:${profile.id}'),
                  index: index,
                  profile: profile,
                );
              },
            ),
          ),
        if (controller.errors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '${controller.errors.length} 个配置文件读取失败：'
              '${controller.errors.join('；')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// 布局里某个组标题后面的连续条目数（组内配置数）。
int _groupSize(List<LayoutNode> rows, int headerIndex) {
  var count = 0;
  for (var i = headerIndex + 1; i < rows.length && !rows[i].isGroup; i++) {
    count++;
  }
  return count;
}

/// 分组标题行：整组可拖（拖把手，或触屏长按），⋮ 承载组管理操作。
class _GroupTile extends StatelessWidget {
  const _GroupTile({
    super.key,
    required this.index,
    required this.name,
    required this.memberCount,
  });

  final int index;
  final String name;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                ),
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$memberCount 个',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('group-menu-$name'),
                  tooltip: '分组管理',
                  icon: const Icon(Icons.more_vert, size: 18),
                  padding: EdgeInsets.zero,
                  onSelected: (value) => _onMenu(context, value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'create', child: Text('在组内新建配置')),
                    PopupMenuItem(value: 'rename', child: Text('重命名分组')),
                    PopupMenuItem(value: 'clear', child: Text('清空分组（删配置）')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'delete', child: Text('删除分组（留配置）')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, String value) async {
    switch (value) {
      case 'create':
        await ProfileActions.create(context, inGroup: name);
      case 'rename':
        await ProfileActions.renameGroup(context, name);
      case 'clear':
        await ProfileActions.clearGroup(context, name);
      case 'delete':
        await ProfileActions.deleteGroup(context, name);
    }
  }
}

/// 配置行：点击进编辑器，⋮ 承载单配置操作；把手（或长按）拖动排序。
class _ProfileTile extends StatelessWidget {
  const _ProfileTile({super.key, required this.index, required this.profile});

  final int index;
  final CoefficientProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final echoMax = ScoreCalculator.roundTo2(
      ScoreCalculator.echoMaxRaw(profile.coefficients),
    );
    final filled = profile.coefficients.values.where((v) => v > 0).length;

    return ReorderableDelayedDragStartListener(
      index: index,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: InkWell(
          onTap: () => ProfileActions.edit(context, profile),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        profile.isAllZero
                            ? '全部系数为 0，尚未配置'
                            : '已设置 $filled/13 项 · 单件理论最高 '
                                  '${Format.score(echoMax)}分 · 五件合计 '
                                  '${Format.score(echoMax * 5)}分',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: profile.isAllZero
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '更新于 ${Format.dateTime(profile.updatedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) => _onMenu(context, value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑系数')),
                    PopupMenuItem(value: 'duplicate', child: Text('复制为新配置')),
                    PopupMenuItem(value: 'copy', child: Text('复制分享链接')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'delete', child: Text('删除配置')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, String value) async {
    switch (value) {
      case 'edit':
        await ProfileActions.edit(context, profile);
      case 'duplicate':
        await ProfileActions.duplicate(context, profile);
      case 'copy':
        await ProfileActions.copyToClipboard(context, [profile]);
      case 'delete':
        await ProfileActions.delete(context, profile);
    }
  }
}

/// 顶部的共享配置提示：文字说明 + 点击交给系统浏览器打开仓库目录。
///
/// 应用自身不发起任何网络请求，链接由操作系统的外部浏览器处理，
/// 与侧栏「GitHub 仓库」入口是同一种方式。
class _ShareBanner extends StatelessWidget {
  const _ShareBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_download_outlined, size: 22, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GitHub 仓库里有社区分享的现成配置，复制内容后用右上 ⋮ →「从剪贴板导入配置」载入',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '也欢迎用 ⋮ →「复制分享链接」把自己的配置发过来，一起丰富配置库',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _open(context),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('打开'),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    try {
      final launched = await launchUrl(
        Uri.parse(AppConstants.sharedProfilesUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        Dialogs.snack(context, '无法打开浏览器，请手动访问 GitHub 仓库');
      }
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }
}
