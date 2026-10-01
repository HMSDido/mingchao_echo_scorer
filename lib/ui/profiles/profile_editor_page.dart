import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/util/format.dart';
import '../../data/catalog/substat_type.dart';
import '../../data/models/coefficients.dart';
import '../../data/models/coefficient_profile.dart';
import '../../domain/score_calculator.dart';
import '../../state/profile_controller.dart';
import '../widgets/dialogs.dart';

/// 角色系数编辑页：13 项系数录入 + 名称修改 + 保存/删除。
class ProfileEditorPage extends StatefulWidget {
  const ProfileEditorPage({required this.profileId, super.key});

  final String profileId;

  @override
  State<ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<ProfileEditorPage> {
  final Map<SubstatType, TextEditingController> _inputs = {};

  late CoefficientProfile _profile;
  late String _name;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    final loaded = context.read<ProfileController>().byId(widget.profileId);
    if (loaded == null) {
      _missing = true;
      _profile = CoefficientProfile.create('');
      _name = '';
      return;
    }
    _profile = loaded;
    _name = loaded.name;
    for (final type in SubstatType.values) {
      final value = loaded.coefficients[type] ?? 0;
      _inputs[type] = TextEditingController(
        text: value == 0 ? '' : value.toStringAsFixed(coefficientDecimalPlaces),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _inputs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Coefficients get _coefficients => {
    for (final type in SubstatType.values)
      type: quantizeCoefficient(
        double.tryParse((_inputs[type]?.text ?? '').trim()) ?? 0,
      ),
  };

  bool get _dirty {
    if (_name.trim() != _profile.name) return true;
    final next = _coefficients;
    for (final type in SubstatType.values) {
      if (next[type] != (_profile.coefficients[type] ?? 0)) return true;
    }
    return false;
  }

  Future<void> _rename() async {
    final name = await Dialogs.promptText(
      context,
      title: '重命名配置',
      label: '配置名称',
      initial: _name,
      confirmLabel: '重命名',
    );
    if (name == null) return;
    setState(() => _name = name);
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final choice = await Dialogs.promptUnsaved(
      context,
      title: '保存对「${_profile.name}」的更改？',
      message: '不保存的话，本次修改的系数会丢失。',
    );
    if (choice == UnsavedChoice.cancel) return false;
    if (!mounted) return true;
    if (choice == UnsavedChoice.save) return _save();
    return true;
  }

  Future<bool> _save() async {
    final controller = context.read<ProfileController>();
    try {
      final saved = await controller.save(
        _profile.copyWith(
          name: _name.trim().isEmpty ? _profile.name : _name.trim(),
          coefficients: _coefficients,
        ),
      );
      if (!mounted) return true;
      setState(() {
        _profile = saved;
        _name = saved.name;
      });
      Dialogs.snack(context, '已保存「${saved.name}」');
      return true;
    } on Exception catch (error) {
      if (mounted) Dialogs.error(context, error);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_missing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.expand());
    }

    final theme = Theme.of(context);
    final coefficients = _coefficients;
    final echoMax = ScoreCalculator.roundTo2(
      ScoreCalculator.echoMaxRaw(coefficients),
    );
    final filled = coefficients.values.where((value) => value > 0).length;
    final wide = MediaQuery.sizeOf(context).width >= 720;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // 在 await 之前取好 Navigator，避免跨异步间隙使用 context。
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) navigator.pop();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (_dirty) _save();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              titleSpacing: 8,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _name.trim().isEmpty ? '未命名配置' : _name.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: '重命名配置',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: _rename,
                  ),
                  if (_dirty)
                    Text(
                      '未保存',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              actions: [
                FilledButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                  onPressed: _dirty ? _save : null,
                ),
                const SizedBox(width: 12),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        children: [
                          for (final type in SubstatType.values) ...[
                            _CoefficientRow(
                              type: type,
                              controller: _inputs[type]!,
                              compact: !wide,
                              onChanged: () => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '已设置 $filled/13 项 · 单件理论最高 '
                              '${Format.score(echoMax)}分 · 五件合计 '
                              '${Format.score(echoMax * 5)}分',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '理论最高分 = 13 项「系数 × 该属性最高档位数值」中最大的 5 项之和',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: filled == 0
                            ? null
                            : () => setState(() {
                                for (final controller in _inputs.values) {
                                  controller.clear();
                                }
                              }),
                        child: const Text('全部清零'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoefficientRow extends StatelessWidget {
  const _CoefficientRow({
    required this.type,
    required this.controller,
    required this.compact,
    required this.onChanged,
  });

  final SubstatType type;
  final TextEditingController controller;
  final bool compact;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppPalette.onAccent(context, AppPalette.attribute(type));
    final value = quantizeCoefficient(double.tryParse(controller.text) ?? 0);
    final best = value * type.maxValue;

    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          type.label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );

    final field = SizedBox(
      width: 108,
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: const InputDecoration(hintText: '0'),
        style: theme.textTheme.bodyMedium,
      ),
    );

    final hint = Text(
      '满档 ${type.displayValueOf(type.maxTier)} · '
      '单条最多 +${Format.score(best)} 分',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: value > 0
            ? AppPalette.attributeSoft(context, type)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value > 0
              ? color.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [label, const Spacer(), field]),
                const SizedBox(height: 4),
                hint,
              ],
            )
          : Row(
              children: [
                SizedBox(width: 170, child: label),
                field,
                const SizedBox(width: 14),
                Expanded(child: hint),
              ],
            ),
    );
  }
}
