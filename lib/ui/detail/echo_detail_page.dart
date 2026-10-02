import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme/palette.dart';
import '../../data/catalog/substat_type.dart';
import '../../data/models/coefficients.dart';
import '../../data/models/echo_entry.dart';
import '../../domain/expected_max_calculator.dart';
import '../../domain/probability_calculator.dart';
import '../../domain/score_calculator.dart';
import '../../state/workspace_controller.dart';
import '../widgets/dialogs.dart';
import 'output_panel.dart';
import 'substat_row.dart';

/// 声骸详情页：13 条词条输入 + 当前评分 / 预期最高分 / 目标分概率三项输出。
///
/// 草稿只在页面内修改，「保存本声骸」才把它写回评分文件（对应需求里
/// 「可以把单个声骸的分数保存回大文件中，替换这一项数据」）。
class EchoDetailPage extends StatefulWidget {
  const EchoDetailPage({required this.fileId, required this.slot, super.key});

  final String fileId;
  final int slot;

  @override
  State<EchoDetailPage> createState() => _EchoDetailPageState();
}

class _EchoDetailPageState extends State<EchoDetailPage> {
  late EchoEntry _draft;
  late EchoEntry _original;
  late TextEditingController _target;
  void Function()? _disposeGuard;

  @override
  void initState() {
    super.initState();
    final workspace = context.read<WorkspaceController>();
    final echo =
        workspace.byId(widget.fileId)?.echoAt(widget.slot) ??
        EchoEntry.create(widget.slot);
    _draft = echo;
    _original = echo;
    _target = TextEditingController(text: _targetTextOf(echo.targetScore));
    _disposeGuard = workspace.registerGuard(_confirmLeave);
  }

  @override
  void dispose() {
    _disposeGuard?.call();
    _target.dispose();
    super.dispose();
  }

  static String _targetTextOf(double? value) =>
      value == null ? '' : value.toStringAsFixed(2);

  bool get _dirty => !_draft.sameContentAs(_original);

  void _setTier(SubstatType type, int tier) =>
      setState(() => _draft = _draft.withTier(type, tier));

  void _onTargetChanged(String raw) {
    final parsed = double.tryParse(raw.trim());
    setState(() {
      _draft = parsed == null || !parsed.isFinite
          ? _draft.copyWith(clearTargetScore: true)
          : _draft.copyWith(targetScore: ScoreCalculator.roundTo2(parsed));
    });
  }

  void _saveEcho() {
    final workspace = context.read<WorkspaceController>();
    workspace.updateEcho(widget.fileId, _draft);
    setState(() => _original = _draft);
    Dialogs.snack(context, '已把「${_draft.name}」写回评分文件，记得保存文件');
  }

  void _resetDraft() {
    setState(() {
      _draft = _original;
      _target.text = _targetTextOf(_original.targetScore);
    });
  }

  Future<void> _rename() async {
    final name = await Dialogs.promptText(
      context,
      title: '重命名声骸',
      label: '名称',
      initial: _draft.name,
      hint: EchoEntry.defaultNameOf(widget.slot),
      confirmLabel: '重命名',
    );
    if (name == null || name == _draft.name) return;
    setState(() => _draft = _draft.copyWith(name: name));
  }

  /// 返回 true 表示可以离开。没有改动时直接放行（类似 Word）。
  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final choice = await Dialogs.promptUnsaved(
      context,
      title: '保存「${_draft.name}」的改动？',
      message:
          '「保存」会把这个声骸的数据写回评分文件；'
          '写回后仍需在总览页保存文件才会落盘。\n'
          '「不保存」会丢弃本次在详情页里的改动。',
    );
    if (choice == UnsavedChoice.cancel) return false;
    if (!mounted) return true;
    if (choice == UnsavedChoice.save) _saveEcho();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final file = workspace.byId(widget.fileId);
    if (file == null) {
      // 文件在详情页之外被关掉了：退回总览。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.expand());
    }

    final coefficients = file.coefficients;
    final score = ScoreCalculator.scoreEcho(_draft, coefficients);
    final expected = ExpectedMaxCalculator.calculate(
      tiers: _draft.tiers,
      coefficients: coefficients,
    );
    final probability = _draft.targetScore == null
        ? null
        : ProbabilityCalculator.reachProbability(
            tiers: _draft.tiers,
            coefficients: coefficients,
            targetScore: _draft.targetScore!,
          );

    final wide =
        MediaQuery.sizeOf(context).width >= AppConstants.compactWidthBreakpoint;

    final outputs = OutputPanel(
      score: score,
      expectedMax: expected,
      probability: probability,
      targetController: _target,
      onTargetChanged: _onTargetChanged,
      overFilled: score.isOverFilled,
    );
    final inputs = _InputList(
      draft: _draft,
      coefficients: coefficients,
      useDropdown: wide,
      onTierChanged: _setTier,
    );

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
            if (_dirty) _saveEcho();
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
                      '${file.name} · ${_draft.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_dirty)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: _UnsavedBadge(),
                    ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: '重命名声骸',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _rename,
                ),
                if (wide)
                  TextButton.icon(
                    icon: const Icon(Icons.undo),
                    label: const Text('撤销改动'),
                    onPressed: _dirty ? _resetDraft : null,
                  )
                else
                  IconButton(
                    tooltip: '撤销改动',
                    icon: const Icon(Icons.undo),
                    onPressed: _dirty ? _resetDraft : null,
                  ),
                const SizedBox(width: 4),
                if (wide)
                  FilledButton.icon(
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存本声骸'),
                    onPressed: _dirty ? _saveEcho : null,
                  )
                else
                  IconButton(
                    tooltip: '保存本声骸',
                    icon: const Icon(Icons.save_outlined),
                    onPressed: _dirty ? _saveEcho : null,
                  ),
                const SizedBox(width: 12),
              ],
            ),
            body: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: inputs,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 400,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: outputs,
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(14),
                    children: [outputs, const SizedBox(height: 14), inputs],
                  ),
          ),
        ),
      ),
    );
  }
}

class _UnsavedBadge extends StatelessWidget {
  const _UnsavedBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '未保存',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InputList extends StatelessWidget {
  const _InputList({
    required this.draft,
    required this.coefficients,
    required this.useDropdown,
    required this.onTierChanged,
  });

  final EchoEntry draft;
  final Coefficients coefficients;
  final bool useDropdown;
  final void Function(SubstatType type, int tier) onTierChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = EchoEntry.maxSubstats - draft.filledCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '副词条档位',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '已选 ${draft.filledCount}/${EchoEntry.maxSubstats}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: remaining < 0
                    ? theme.colorScheme.error
                    : theme.colorScheme.outline,
                fontWeight: remaining < 0 ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            const Spacer(),
            Text(
              '从 13 项中最多选 5 项',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final type in SubstatType.values) ...[
          SubstatRow(
            type: type,
            tier: draft.tierOf(type),
            coefficient: coefficients[type] ?? 0,
            useDropdown: useDropdown,
            onChanged: (tier) => onTierChanged(type, tier),
          ),
          const SizedBox(height: 8),
        ],
        if (draft.filledCount > 0) ...[
          const Divider(height: 20),
          Text(
            '已选词条（点 × 可清除）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final type in SubstatType.values)
                if (draft.tierOf(type) > 0)
                  _SelectedChip(
                    type: type,
                    tier: draft.tierOf(type),
                    onClear: () => onTierChanged(type, 0),
                  ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({
    required this.type,
    required this.tier,
    required this.onClear,
  });

  final SubstatType type;
  final int tier;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final color = AppPalette.onAccent(context, AppPalette.attribute(type));
    return InputChip(
      visualDensity: VisualDensity.compact,
      avatar: CircleAvatar(radius: 4, backgroundColor: color),
      label: Text(
        '${type.label} $tier档',
        style: TextStyle(color: color, fontSize: 12),
      ),
      backgroundColor: AppPalette.attributeSoft(context, type),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      onDeleted: onClear,
      deleteIconColor: color,
    );
  }
}
