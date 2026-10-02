import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/util/file_names.dart';
import '../../core/util/format.dart';
import '../../data/models/coefficient_profile.dart';
import '../../data/models/score_file.dart';
import '../../data/models/share_link.dart';
import '../../domain/score_calculator.dart';
import '../../state/profile_controller.dart';
import '../../state/workspace_controller.dart';
import '../widgets/dialogs.dart';
import 'share_actions.dart';

/// 评分文件的界面级操作：把控制器动作和对话框/提示串起来。
class FileActions {
  const FileActions._();

  static Future<void> create(BuildContext context, {String? inGroup}) async {
    final workspace = context.read<WorkspaceController>();
    final name = await Dialogs.promptText(
      context,
      title: '新建评分文件',
      label: '文件名',
      initial: FileNames.deduplicate(
        '新建评分文件',
        workspace.diskFiles.map((file) => file.name),
      ),
      hint: '会以此名创建一个文件夹来保存评分',
      confirmLabel: '新建',
    );
    if (name == null || !context.mounted) return;
    try {
      await workspace.createFile(name, inGroup: inGroup);
      if (context.mounted) Dialogs.snack(context, '已新建「$name」，请先选择角色');
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }

  // ---------------------------------------------------------------- 分组

  /// 新建分组。
  static Future<void> addGroup(BuildContext context) async {
    final workspace = context.read<WorkspaceController>();
    final name = await Dialogs.promptText(
      context,
      title: '新建分组',
      label: '分组名称',
      hint: '例如按角色或用途归类',
      confirmLabel: '新建',
    );
    if (name == null || !context.mounted) return;
    if (name.trim().isEmpty) {
      Dialogs.snack(context, '分组名称不能为空');
      return;
    }
    if (!workspace.addLayoutGroup(name.trim())) {
      if (context.mounted) {
        Dialogs.snack(context, '已存在同名分组「${name.trim()}」');
      }
    }
  }

  /// 重命名分组。
  static Future<void> renameGroup(BuildContext context, String name) async {
    final workspace = context.read<WorkspaceController>();
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
    if (!workspace.renameLayoutGroup(name, newName.trim())) {
      if (context.mounted) Dialogs.snack(context, '已存在同名分组「$newName」');
    }
  }

  /// 清空分组：删除组内全部评分文件（连文件夹），组本身保留。
  static Future<void> clearGroup(BuildContext context, String name) async {
    final workspace = context.read<WorkspaceController>();
    final members = workspace
        .layoutGroupMemberIds(name)
        .map(workspace.byId)
        .nonNulls
        .toList();
    if (members.isEmpty) {
      Dialogs.snack(context, '分组「$name」里没有文件');
      return;
    }
    final ok = await Dialogs.confirm(
      context,
      title: '清空分组「$name」？',
      message:
          '将删除组内 ${members.length} 个评分文件本身（连同各自的文件夹），'
          '分组保留。有未保存改动时不再逐个询问，直接丢弃。此操作无法撤销。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      final failed = await workspace.deleteFiles(members);
      if (!context.mounted) return;
      final done = members.length - failed.length;
      Dialogs.snack(
        context,
        failed.isEmpty
            ? '已清空分组「$name」（删除 $done 个文件）'
            : '已删除 $done 个文件，${failed.length} 个失败',
      );
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }

  /// 删除分组本身：组内文件不删，释放到根层。
  static Future<void> deleteGroup(BuildContext context, String name) async {
    final workspace = context.read<WorkspaceController>();
    final count = workspace.layoutGroupMemberIds(name).length;
    final ok = await Dialogs.confirm(
      context,
      title: '删除分组「$name」？',
      message: count == 0
          ? '分组是空的，删除后不影响任何文件。'
          : '只删除分组本身，组内 $count 个文件不会被删除，'
                '而是释放到列表顶部（根层）。',
      confirmLabel: '删除分组',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    workspace.deleteLayoutGroup(name);
    if (context.mounted) Dialogs.snack(context, '已删除分组「$name」');
  }

  /// 从磁盘上尚未打开的文件里挑一个打开。
  static Future<void> open(BuildContext context) async {
    final workspace = context.read<WorkspaceController>();
    try {
      await workspace.refreshDisk();
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
      return;
    }
    if (!context.mounted) return;

    final candidates = workspace.diskFiles
        .where((file) => !workspace.isOpen(file))
        .toList();
    final picked = await Dialogs.pick<ScoreFile>(
      context,
      title: '打开评分文件',
      items: candidates,
      labelBuilder: (file) => file.name,
      subtitleBuilder: (file) {
        final score = ScoreCalculator.scoreFile(
          file.echoes,
          file.coefficients,
          critThreshold: file.critThreshold,
        );
        final profile = file.hasProfile ? file.profileName : '未选择角色';
        return '${Format.scoreWithUnit(score.totalScore)} · $profile · '
            '${Format.dateTime(file.updatedAt)}';
      },
      emptyMessage: workspace.diskFiles.isEmpty
          ? '存储目录里还没有评分文件，先新建一个吧。'
          : '所有文件都已经打开了。',
    );
    if (picked != null) workspace.openFile(picked);
  }

  static Future<void> save(BuildContext context, {ScoreFile? target}) async {
    final workspace = context.read<WorkspaceController>();
    final file = target ?? workspace.activeFile;
    if (file == null) {
      Dialogs.snack(context, '没有打开的评分文件');
      return;
    }
    if (!workspace.isDirty(file)) {
      Dialogs.snack(context, '「${file.name}」没有改动，无需保存');
      return;
    }
    try {
      await workspace.saveFile(file);
      if (context.mounted) Dialogs.snack(context, '已保存「${file.name}」');
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }

  /// 读剪贴板并批量导入评分文件。
  static Future<void> importFromClipboard(BuildContext context) async {
    final workspace = context.read<WorkspaceController>();
    await ShareActions.import(
      context,
      unit: '评分文件',
      run: workspace.importShareText,
    );
  }

  /// 把文件复制成分享链接（含 5 件声骸的档位与系数快照）。
  static Future<void> copyShareLink(
    BuildContext context, {
    ScoreFile? target,
  }) async {
    final workspace = context.read<WorkspaceController>();
    final file = target ?? workspace.activeFile;
    if (file == null) {
      Dialogs.snack(context, '没有打开的评分文件');
      return;
    }
    await ShareActions.copy(
      context,
      ScoreShare.encode(file),
      '已复制「${file.name}」的分享链接',
    );
  }

  /// 把全部已打开文件编码成分享链接一次复制走（一行一个，对方可整批导入）。
  static Future<void> copyAllShareLinks(BuildContext context) async {
    final workspace = context.read<WorkspaceController>();
    final files = workspace.openFiles;
    if (files.isEmpty) {
      Dialogs.snack(context, '没有打开的评分文件');
      return;
    }
    await ShareActions.copy(
      context,
      ScoreShare.encodeAll(files),
      '已复制 ${files.length} 个评分文件的分享链接',
    );
  }

  /// 批量导出：勾选多个文件，把它们的分享链接一次复制进剪贴板。
  static Future<void> exportMany(BuildContext context) async {
    final workspace = context.read<WorkspaceController>();
    final files = workspace.openFiles;
    if (files.isEmpty) {
      Dialogs.snack(context, '没有打开的评分文件');
      return;
    }
    final picked = await Dialogs.pickMulti<ScoreFile>(
      context,
      title: '批量导出评分文件',
      items: files,
      labelBuilder: (file) => file.name,
      hint: '选中的分享链接（各带一行名字说明）将一起复制到剪贴板。',
      emptyMessage: '没有打开的评分文件',
      confirmLabel: '导出',
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    await ShareActions.copy(
      context,
      ScoreShare.encodeAll(picked),
      '已复制 ${picked.length} 个评分文件的分享链接',
    );
  }

  /// 导出本组：把组内全部文件的分享链接一次复制进剪贴板。
  static Future<void> exportGroup(BuildContext context, String name) async {
    final workspace = context.read<WorkspaceController>();
    final members = workspace
        .layoutGroupMemberIds(name)
        .map(workspace.byId)
        .nonNulls
        .toList();
    if (members.isEmpty) {
      Dialogs.snack(context, '分组「$name」里没有文件');
      return;
    }
    await ShareActions.copy(
      context,
      ScoreShare.encodeAll(members),
      '已复制分组「$name」的 ${members.length} 个分享链接',
    );
  }

  static Future<void> rename(BuildContext context, ScoreFile file) async {
    final workspace = context.read<WorkspaceController>();
    final name = await Dialogs.promptText(
      context,
      title: '重命名评分文件',
      label: '文件名',
      initial: file.name,
      confirmLabel: '重命名',
    );
    if (name == null || name == file.name || !context.mounted) return;
    try {
      await workspace.renameFile(file, name);
      if (context.mounted) {
        Dialogs.snack(
          context,
          '已重命名为「${workspace.byId(file.id)?.name ?? name}」',
        );
      }
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }

  /// 关闭文件；有改动时按 Word 的习惯询问「保存 / 不保存 / 取消」。
  static Future<bool> close(BuildContext context, ScoreFile file) async {
    final workspace = context.read<WorkspaceController>();
    if (workspace.isDirty(file)) {
      final choice = await Dialogs.promptUnsaved(
        context,
        title: '保存对「${file.name}」的更改？',
        message: '不保存的话，本次的改动会丢失。',
      );
      if (choice == UnsavedChoice.cancel || !context.mounted) return false;
      if (choice == UnsavedChoice.save) {
        try {
          await workspace.saveFile(file);
        } on Exception catch (error) {
          if (context.mounted) Dialogs.error(context, error);
          return false;
        }
      }
    }
    await workspace.closeFile(file);
    return true;
  }

  static Future<void> delete(BuildContext context, ScoreFile file) async {
    final workspace = context.read<WorkspaceController>();
    final ok = await Dialogs.confirm(
      context,
      title: '删除「${file.name}」？',
      message: '会连同它的文件夹一起从磁盘上删除，且无法撤销。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await workspace.deleteFile(file);
      if (context.mounted) Dialogs.snack(context, '已删除「${file.name}」');
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }

  /// 批量删除：从已打开的文件里勾选多个，连同各自的文件夹一起删掉。
  static Future<void> deleteMany(BuildContext context) async {
    final workspace = context.read<WorkspaceController>();
    final files = workspace.openFiles;
    if (files.isEmpty) {
      Dialogs.snack(context, '没有打开的评分文件');
      return;
    }
    final picked = await Dialogs.pickMulti<ScoreFile>(
      context,
      title: '批量删除评分文件',
      items: files,
      labelBuilder: (file) => file.name,
      subtitleBuilder: (file) {
        final score = ScoreCalculator.scoreFile(
          file.echoes,
          file.coefficients,
          critThreshold: file.critThreshold,
        );
        final who = file.hasProfile ? file.profileName : '未选择角色';
        return '${Format.scoreWithUnit(score.totalScore)} '
            '${Format.rating(score.totalRating)} · $who'
            '${workspace.isDirty(file) ? ' · 有未保存的改动' : ''}';
      },
      hint: '会连同选中的文件夹一起从磁盘上删除，且无法撤销。',
      emptyMessage: '没有打开的评分文件',
      confirmLabel: '删除',
      destructive: true,
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    try {
      final failed = await workspace.deleteFiles(picked);
      if (!context.mounted) return;
      final done = picked.length - failed.length;
      if (failed.isEmpty) {
        Dialogs.snack(context, '已删除 $done 个评分文件');
      } else {
        await Dialogs.alert(
          context,
          title: '已删除 $done 个评分文件，${failed.length} 个失败',
          message: failed.map((file) => '「${file.name}」').join('\n'),
        );
      }
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }

  /// 选择/更换角色系数配置，并把系数快照代入文件。
  static Future<void> chooseProfile(
    BuildContext context,
    ScoreFile file,
  ) async {
    final workspace = context.read<WorkspaceController>();
    final profiles = context.read<ProfileController>();
    try {
      await profiles.reload();
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
      return;
    }
    if (!context.mounted) return;

    final picked = await Dialogs.pick<CoefficientProfile>(
      context,
      title: file.hasProfile ? '更换角色系数配置' : '选择角色',
      items: profiles.profiles,
      labelBuilder: (profile) => profile.name,
      subtitleBuilder: (profile) => profile.isAllZero
          ? '全部系数为 0'
          : '理论最高分 ${Format.score(ScoreCalculator.roundTo2(ScoreCalculator.echoMaxRaw(profile.coefficients)))}／件',
      emptyMessage: '还没有角色系数配置。请先到「编辑角色系数」新建一份。',
      groupRows: profiles.pickerLayoutRows,
      idBuilder: (profile) => profile.id,
    );
    if (picked == null || !context.mounted) return;
    workspace.applyProfile(file, picked);
    Dialogs.snack(context, '已套用「${picked.name}」的系数，记得保存');
  }
}
