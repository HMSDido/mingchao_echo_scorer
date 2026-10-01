import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/io/transfer.dart';
import '../../core/util/file_names.dart';
import '../../core/util/format.dart';
import '../../data/models/coefficient_profile.dart';
import '../../data/models/score_file.dart';
import '../../domain/score_calculator.dart';
import '../../state/profile_controller.dart';
import '../../state/workspace_controller.dart';
import '../widgets/dialogs.dart';

/// 评分文件的界面级操作：把控制器动作和对话框/提示串起来。
class FileActions {
  const FileActions._();

  static Future<void> create(BuildContext context) async {
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
      await workspace.createFile(name);
      if (context.mounted) Dialogs.snack(context, '已新建「$name」，请先选择角色');
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
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
        final score = ScoreCalculator.scoreFile(file.echoes, file.coefficients);
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

  static Future<void> importFile(BuildContext context) async {
    final workspace = context.read<WorkspaceController>();
    try {
      final json = await Transfer.pickJson();
      if (json == null || !context.mounted) return;
      await workspace.importScoreJson(json);
      if (context.mounted) Dialogs.snack(context, '导入成功');
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }

  static Future<void> export(BuildContext context, {ScoreFile? target}) async {
    final workspace = context.read<WorkspaceController>();
    final file = target ?? workspace.activeFile;
    if (file == null) {
      Dialogs.snack(context, '没有打开的评分文件');
      return;
    }
    try {
      final path = await workspace.exportScoreJson(file);
      if (!context.mounted) return;
      Dialogs.snack(context, path == null ? '已取消导出' : '已导出到：$path');
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
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
    );
    if (picked == null || !context.mounted) return;
    workspace.applyProfile(file, picked);
    Dialogs.snack(context, '已套用「${picked.name}」的系数，记得保存');
  }
}
