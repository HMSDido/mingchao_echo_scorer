import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/util/file_names.dart';
import '../../core/util/format.dart';
import '../../data/models/coefficient_profile.dart';
import '../../data/models/id_generator.dart';
import '../../data/models/share_link.dart';
import '../../state/profile_controller.dart';
import '../profiles/profile_editor_page.dart';
import '../widgets/dialogs.dart';
import 'share_actions.dart';

/// 角色系数配置的界面级操作。
class ProfileActions {
  const ProfileActions._();

  static Future<void> edit(BuildContext context, CoefficientProfile profile) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProfileEditorPage(profileId: profile.id),
        ),
      );

  static Future<void> create(BuildContext context, {String? inGroup}) async {
    final profiles = context.read<ProfileController>();
    final name = await Dialogs.promptText(
      context,
      title: '新建角色系数配置',
      label: '配置名称',
      initial: FileNames.deduplicate(
        '新建配置',
        profiles.profiles.map((item) => item.name),
      ),
      hint: '例如「01长离」「21守岸人」（链数+角色名）',
      confirmLabel: '新建',
    );
    if (name == null || !context.mounted) return;
    try {
      final created = await profiles.create(name);
      if (inGroup != null) profiles.placeInLayoutGroup(inGroup, created.id);
      if (context.mounted) await edit(context, created);
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }

  // ---------------------------------------------------------------- 分组

  /// 重命名分组；撞名或非法名时提示不落库。
  static Future<void> renameGroup(BuildContext context, String name) async {
    final profiles = context.read<ProfileController>();
    final newName = await Dialogs.promptText(
      context,
      title: '重命名分组',
      label: '分组名称',
      initial: name,
      confirmLabel: '重命名',
    );
    if (newName == null || !context.mounted) return;
    if (newName.trim().isEmpty) {
      Dialogs.snack(context, '分组名称不能为空');
      return;
    }
    if (!profiles.renameLayoutGroup(name, newName.trim())) {
      if (context.mounted) Dialogs.snack(context, '已存在同名分组「$newName」');
    }
  }

  /// 新建分组。
  static Future<void> addGroup(BuildContext context) async {
    final profiles = context.read<ProfileController>();
    final name = await Dialogs.promptText(
      context,
      title: '新建分组',
      label: '分组名称',
      hint: '例如按角色归类：「绯雪」「忌炎」',
      confirmLabel: '新建',
    );
    if (name == null || !context.mounted) return;
    if (name.trim().isEmpty) {
      Dialogs.snack(context, '分组名称不能为空');
      return;
    }
    if (!profiles.addLayoutGroup(name.trim())) {
      if (context.mounted) Dialogs.snack(context, '已存在同名分组「${name.trim()}」');
    }
  }

  /// 清空分组：删除组内全部配置文件，组本身保留。
  static Future<void> clearGroup(BuildContext context, String name) async {
    final profiles = context.read<ProfileController>();
    final members = profiles
        .layoutGroupMemberIds(name)
        .map(profiles.byId)
        .nonNulls
        .toList();
    if (members.isEmpty) {
      Dialogs.snack(context, '分组「$name」里没有配置');
      return;
    }
    if (context.mounted) {
      final ok = await Dialogs.confirm(
        context,
        title: '清空分组「$name」？',
        message:
            '将删除组内 ${members.length} 个配置文件本身，分组保留。'
            '已套用这些系数的评分文件不受影响（系数是快照保存的）。此操作无法撤销。',
        confirmLabel: '清空',
        destructive: true,
      );
      if (!ok || !context.mounted) return;
    }
    try {
      final failedIds = await profiles.deleteMany(members);
      if (!context.mounted) return;
      final done = members.length - failedIds.length;
      Dialogs.snack(
        context,
        failedIds.isEmpty
            ? '已清空分组「$name」（删除 $done 个配置）'
            : '已删除 $done 个配置，${failedIds.length} 个失败',
      );
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }

  /// 删除分组本身：组内配置不删，释放到根层。
  static Future<void> deleteGroup(BuildContext context, String name) async {
    final profiles = context.read<ProfileController>();
    final count = profiles.layoutGroupMemberIds(name).length;
    final ok = await Dialogs.confirm(
      context,
      title: '删除分组「$name」？',
      message: count == 0
          ? '分组是空的，删除后不影响任何配置。'
          : '只删除分组本身，组内 $count 个配置不会被删除，'
                '而是释放到列表顶部（根层）。',
      confirmLabel: '删除分组',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    profiles.deleteLayoutGroup(name);
    if (context.mounted) Dialogs.snack(context, '已删除分组「$name」');
  }

  /// 以现有配置为模板复制一份（系数照搬，名字另取）。
  static Future<void> duplicate(
    BuildContext context,
    CoefficientProfile profile,
  ) async {
    final profiles = context.read<ProfileController>();
    final name = await Dialogs.promptText(
      context,
      title: '复制配置',
      label: '新配置名称',
      initial: FileNames.deduplicate(
        '${profile.name} 副本',
        profiles.profiles.map((item) => item.name),
      ),
      confirmLabel: '复制',
    );
    if (name == null || !context.mounted) return;
    try {
      final now = DateTime.now();
      final copy = CoefficientProfile(
        id: newId(),
        name: name,
        coefficients: profile.coefficients,
        createdAt: now,
        updatedAt: now,
      );
      final saved = await profiles.save(copy);
      if (context.mounted) await edit(context, saved);
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }

  /// 把配置编码成分享链接写进剪贴板；多条按行拼接，一次复制全部。
  static Future<void> copyToClipboard(
    BuildContext context,
    List<CoefficientProfile> profiles,
  ) async {
    if (profiles.isEmpty) {
      Dialogs.snack(context, '没有可复制的配置');
      return;
    }
    await ShareActions.copy(
      context,
      ProfileShare.encodeAll(profiles),
      '已复制 ${profiles.length} 个配置到剪贴板',
    );
  }

  /// 读剪贴板并批量导入配置。
  static Future<void> importFromClipboard(BuildContext context) async {
    final profiles = context.read<ProfileController>();
    await ShareActions.import(
      context,
      unit: '配置',
      run: profiles.importShareText,
    );
  }

  /// 批量删除配置：勾选多个，一次删掉。
  static Future<void> deleteMany(BuildContext context) async {
    final controller = context.read<ProfileController>();
    final items = controller.profiles;
    if (items.isEmpty) {
      Dialogs.snack(context, '没有可删除的配置');
      return;
    }
    final picked = await Dialogs.pickMulti<CoefficientProfile>(
      context,
      title: '批量删除配置',
      items: items,
      labelBuilder: (profile) => profile.name,
      subtitleBuilder: (profile) => '更新于 ${Format.dateTime(profile.updatedAt)}',
      hint:
          '已经套用这些系数的评分文件不受影响（系数是快照保存的），'
          '但之后无法再选到它们。此操作无法撤销。',
      emptyMessage: '还没有角色系数配置',
      confirmLabel: '删除',
      destructive: true,
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    try {
      final failedIds = await controller.deleteMany(picked);
      if (!context.mounted) return;
      final failed = picked
          .where((item) => failedIds.contains(item.id))
          .toList();
      final done = picked.length - failed.length;
      if (failed.isEmpty) {
        Dialogs.snack(context, '已删除 $done 个配置');
      } else {
        await Dialogs.alert(
          context,
          title: '已删除 $done 个配置，${failed.length} 个失败',
          message: failed.map((profile) => '「${profile.name}」').join('\n'),
        );
      }
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }

  static Future<void> delete(
    BuildContext context,
    CoefficientProfile profile,
  ) async {
    final profiles = context.read<ProfileController>();
    final ok = await Dialogs.confirm(
      context,
      title: '删除「${profile.name}」？',
      message:
          '已经套用这份系数的评分文件不受影响（系数是快照保存的），'
          '但之后无法再选到它。此操作无法撤销。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await profiles.delete(profile.id);
      if (context.mounted) Dialogs.snack(context, '已删除「${profile.name}」');
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }
}
