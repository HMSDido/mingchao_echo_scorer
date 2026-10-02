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

  /// 单按钮提示框，用于展示多行结果或错误明细（内容可滚动）。
  static Future<void> alert(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = '知道了',
  }) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(child: Text(message)),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(confirmLabel),
        ),
      ],
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

  /// 从若干选项中勾选多项；取消返回 null，确定返回勾选项（至少一项）。
  static Future<List<T>?> pickMulti<T>(
    BuildContext context, {
    required String title,
    required List<T> items,
    required String Function(T item) labelBuilder,
    String Function(T item)? subtitleBuilder,
    String? hint,
    String? emptyMessage,
    String confirmLabel = '确定',
    bool destructive = false,
  }) => showDialog<List<T>>(
    context: context,
    builder: (dialogContext) => _MultiPickDialog<T>(
      title: title,
      items: items,
      labelBuilder: labelBuilder,
      subtitleBuilder: subtitleBuilder,
      hint: hint,
      emptyMessage: emptyMessage,
      confirmLabel: confirmLabel,
      destructive: destructive,
    ),
  );

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

/// [Dialogs.pickMulti] 的对话框内容：勾选若干项后一次性返回。
class _MultiPickDialog<T> extends StatefulWidget {
  const _MultiPickDialog({
    required this.title,
    required this.items,
    required this.labelBuilder,
    required this.subtitleBuilder,
    required this.hint,
    required this.emptyMessage,
    required this.confirmLabel,
    required this.destructive,
  });

  final String title;
  final List<T> items;
  final String Function(T item) labelBuilder;
  final String Function(T item)? subtitleBuilder;
  final String? hint;
  final String? emptyMessage;
  final String confirmLabel;
  final bool destructive;

  @override
  State<_MultiPickDialog<T>> createState() => _MultiPickDialogState<T>();
}

class _MultiPickDialogState<T> extends State<_MultiPickDialog<T>> {
  final Set<int> _selected = {};

  void _toggle(int index, bool? checked) {
    setState(() {
      if (checked ?? false) {
        _selected.add(index);
      } else {
        _selected.remove(index);
      }
    });
  }

  void _submit() {
    if (_selected.isEmpty) return;
    Navigator.of(context)
        .pop([for (final index in _selected) widget.items[index]]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SizedBox(
        width: 420,
        child: widget.items.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  widget.emptyMessage ?? '暂无可选项',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.hint != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: Text(
                        widget.hint!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (
                          var index = 0;
                          index < widget.items.length;
                          index++
                        )
                          CheckboxListTile(
                            dense: true,
                            value: _selected.contains(index),
                            onChanged: (checked) => _toggle(index, checked),
                            title: Text(
                              widget.labelBuilder(widget.items[index]),
                            ),
                            subtitle: widget.subtitleBuilder == null
                                ? null
                                : Text(
                                    widget.subtitleBuilder!(
                                      widget.items[index],
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      '已选 ${_selected.length} 项',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                )
              : null,
          onPressed: _selected.isEmpty ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
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
