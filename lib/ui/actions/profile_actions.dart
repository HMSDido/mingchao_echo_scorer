import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/io/transfer.dart';
import '../../core/util/file_names.dart';
import '../../data/models/coefficient_profile.dart';
import '../../data/models/id_generator.dart';
import '../../state/app_scope.dart';
import '../../state/profile_controller.dart';
import '../profiles/profile_editor_page.dart';
import '../widgets/dialogs.dart';

/// 角色系数配置的界面级操作。
class ProfileActions {
  const ProfileActions._();

  static Future<void> edit(BuildContext context, CoefficientProfile profile) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProfileEditorPage(profileId: profile.id),
        ),
      );

  static Future<void> create(BuildContext context) async {
    final profiles = context.read<ProfileController>();
    final name = await Dialogs.promptText(
      context,
      title: '新建角色系数配置',
      label: '配置名称',
      initial: FileNames.deduplicate(
        '新建配置',
        profiles.profiles.map((item) => item.name),
      ),
      hint: '例如「长离」「守岸人」',
      confirmLabel: '新建',
    );
    if (name == null || !context.mounted) return;
    try {
      final created = await profiles.create(name);
      if (context.mounted) await edit(context, created);
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
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

  static Future<void> importJson(BuildContext context) async {
    final profiles = context.read<ProfileController>();
    try {
      final json = await Transfer.pickJson(dialogTitle: '导入角色系数配置');
      if (json == null || !context.mounted) return;
      final imported = await profiles.importJson(json);
      if (context.mounted) {
        Dialogs.snack(context, '已导入「${imported.name}」');
      }
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }

  static Future<void> export(
    BuildContext context,
    CoefficientProfile profile,
  ) async {
    final scope = context.read<AppScope>();
    try {
      final path = await Transfer.saveJson(
        suggestedName: '${profile.name}-角色系数',
        json: profile.toJson(),
        fallbackDir: scope.storage.exportsDir,
      );
      if (!context.mounted) return;
      Dialogs.snack(context, path == null ? '已取消导出' : '已导出到：$path');
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
