import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/share_link.dart';
import '../widgets/dialogs.dart';

/// 剪贴板分享的界面级操作：写入分享链接、读取并批量导入后汇总反馈。
///
/// 角色系数配置和评分文件共用这一套交互，只有「导入到哪个控制器」不同。
class ShareActions {
  const ShareActions._();

  static Future<void> copy(
    BuildContext context,
    String text,
    String message,
  ) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) Dialogs.snack(context, message);
  }

  /// 读剪贴板交给 [run] 导入；坏行不中断整批，最后按「成功 X 个 / 跳过 Y 行」反馈。
  static Future<void> import(
    BuildContext context, {
    required String unit,
    required Future<ShareImportSummary> Function(String text) run,
  }) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!context.mounted) return;
    if (text.isEmpty) {
      Dialogs.snack(context, '剪贴板里没有可导入的内容');
      return;
    }
    try {
      final summary = await run(text);
      if (!context.mounted) return;
      final skipped = summary.failures.length;
      final title =
          '成功导入 ${summary.imported} 个$unit'
          '${skipped == 0 ? '' : '，跳过 $skipped 行无效数据'}';
      if (skipped == 0) {
        Dialogs.snack(context, title);
      } else {
        await Dialogs.alert(
          context,
          title: title,
          message: summary.failures.join('\n'),
        );
      }
    } on Exception catch (error) {
      if (context.mounted) Dialogs.error(context, error);
    }
  }
}
