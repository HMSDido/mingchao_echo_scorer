import 'package:flutter/material.dart';

/// 未保存改动的处置选择。
enum UnsavedChoice {
  save('保存'),
  discard('不保存'),
  cancel('取消');

  const UnsavedChoice(this.label);

  final String label;
}

/// 通用的应用内交互：文本输入、确认、未保存提示、消息条。
class Dialogs {
  const Dialogs._();

  static void snack(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  static void error(BuildContext context, Object error) =>
      snack(context, '出错了：$error');

  /// 单行文本输入；确认返回内容，取消返回 null。
  static Future<String?> promptText(
    BuildContext context, {
    required String title,
    required String label,
    String initial = '',
    String? hint,
    String confirmLabel = '确定',
    int maxLength = 60,
    bool allowEmpty = false,
  }) => showDialog<String>(
    context: context,
    builder: (dialogContext) => _TextPromptDialog(
      title: title,
      label: label,
      initial: initial,
      hint: hint,
      confirmLabel: confirmLabel,
      maxLength: maxLength,
      allowEmpty: allowEmpty,
    ),
  );

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = '确定',
    String cancelLabel = '取消',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 380, child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          destructive
              ? FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(dialogContext).colorScheme.error,
                    foregroundColor: Theme.of(dialogContext)
                        .colorScheme
                        .onError,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(confirmLabel),
                )
              : FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(confirmLabel),
                ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 「保存 / 不保存 / 取消」三选；关闭对话框（点遮罩、按 Esc）视为取消。
  static Future<UnsavedChoice> promptUnsaved(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final result = await showDialog<UnsavedChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 380, child: Text(message)),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(UnsavedChoice.cancel),
            child: Text(UnsavedChoice.cancel.label),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(UnsavedChoice.discard),
            child: Text(UnsavedChoice.discard.label),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(UnsavedChoice.save),
            child: Text(UnsavedChoice.save.label),
          ),
        ],
      ),
    );
    return result ?? UnsavedChoice.cancel;
  }

  /// 从若干选项中挑一个；取消返回 null。
  static Future<T?> pick<T>(
    BuildContext context, {
    required String title,
    required List<T> items,
    required String Function(T item) labelBuilder,
    String Function(T item)? subtitleBuilder,
    Widget Function(T item)? leadingBuilder,
    String? emptyMessage,
  }) => showDialog<T>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: SizedBox(
          width: 420,
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    emptyMessage ?? '暂无可选项',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final item in items)
                        ListTile(
                          leading: leadingBuilder?.call(item),
                          title: Text(labelBuilder(item)),
                          subtitle: subtitleBuilder == null
                              ? null
                              : Text(subtitleBuilder(item)),
                          onTap: () => Navigator.of(dialogContext).pop(item),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      );
    },
  );
}

/// [Dialogs.promptText] 的对话框内容。
///
/// 用 StatefulWidget 自己持有 [TextEditingController]，在 [State.dispose] 里释放。
/// 这样控制器只会在对话框退场动画结束、元素真正卸载后才销毁；若在 `showDialog`
/// 返回后立即销毁，退场动画期间的重建会用到已销毁的控制器并抛异常。
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.hint,
    required this.confirmLabel,
    required this.maxLength,
    required this.allowEmpty,
  });

  final String title;
  final String label;
  final String initial;
  final String? hint;
  final String confirmLabel;
  final int maxLength;
  final bool allowEmpty;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initial;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            maxLength: widget.maxLength,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
            ),
            validator: (value) {
              if (widget.allowEmpty) return null;
              return (value == null || value.trim().isEmpty) ? '不能为空' : null;
            },
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
