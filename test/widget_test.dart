import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/app.dart';
import 'package:mingchao_echo_scorer/data/catalog/substat_type.dart';
import 'package:mingchao_echo_scorer/data/models/coefficients.dart';
import 'package:mingchao_echo_scorer/data/models/score_file.dart';
import 'package:mingchao_echo_scorer/data/repositories/background_image_service.dart';
import 'package:mingchao_echo_scorer/data/repositories/profile_repository.dart';
import 'package:mingchao_echo_scorer/data/repositories/score_repository.dart';
import 'package:mingchao_echo_scorer/data/repositories/storage_service.dart';
import 'package:mingchao_echo_scorer/state/app_scope.dart';
import 'package:mingchao_echo_scorer/state/profile_controller.dart';
import 'package:mingchao_echo_scorer/state/settings_controller.dart';
import 'package:mingchao_echo_scorer/state/workspace_controller.dart';
import 'package:mingchao_echo_scorer/ui/detail/echo_detail_page.dart';
import 'package:mingchao_echo_scorer/ui/overview/echo_card.dart';
import 'package:mingchao_echo_scorer/ui/shell/file_panel.dart';
import 'package:mingchao_echo_scorer/ui/shell/nav_rail.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 暴击率/暴击伤害/攻击%/生命%/防御% 系数各 1.0，其余为 0。
///
/// 于是单件理论最高分 = 各项「系数 × 最高档位数值」降序取 5：
/// 暴伤 21.0 + 防御% 14.7 + 攻击% 11.6 + 生命% 11.6 + 暴击率 10.5 = 69.40，
/// 五件合计 347.00。
const Coefficients _fiveCoefficients = {
  SubstatType.critRate: 1.0,
  SubstatType.critDmg: 1.0,
  SubstatType.atkPct: 1.0,
  SubstatType.hpPct: 1.0,
  SubstatType.defPct: 1.0,
};

void main() {
  testWidgets('没有打开文件时给出新建与打开入口', (tester) async {
    await _pumpApp(tester);

    expect(find.text('还没有打开评分文件'), findsOneWidget);
    expect(find.text('新建文件'), findsOneWidget);
    expect(find.text('打开文件'), findsOneWidget);
    expect(find.byType(EchoCard), findsNothing);
  });

  testWidgets('新建的文件提示选择角色，套用配置后代入系数快照', (tester) async {
    final harness = await _pumpApp(tester);
    await harness.runAsync(() async {
      final created = await harness.profiles.create('长离');
      await harness.profiles.save(
        created.copyWith(coefficients: _fiveCoefficients),
      );
      await harness.workspace.createFile('测试文件');
    });
    await tester.pumpAndSettle();

    expect(find.text('「测试文件」还没有选择角色'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '选择角色'));
    await _settle(tester);
    expect(find.text('长离'), findsWidgets);

    await tester.tap(find.text('长离').last);
    await _settle(tester);

    expect(_plainText(tester, 'total-score'), '0.00分 无评级');
    expect(find.textContaining('理论最高 347.00分'), findsOneWidget);
    expect(find.textContaining('角色：长离'), findsOneWidget);

    // 系数是快照：写进了评分文件本身。
    final file = harness.workspace.activeFile!;
    expect(file.profileName, '长离');
    expect(file.coefficients[SubstatType.critRate], 1.0);
    expect(file.coefficients[SubstatType.flatAtk], 0.0);
  });

  testWidgets('总览页显示总分与 5 张声骸卡片', (tester) async {
    await _pumpApp(tester);
    await _seedScoredFile(tester, fileName: '长离-主C');

    expect(_plainText(tester, 'total-score'), '0.00分 无评级');
    expect(find.byType(EchoCard), findsNWidgets(5));
    for (var slot = 0; slot < 5; slot++) {
      expect(find.text('声骸${slot + 1}'), findsOneWidget);
      expect(_plainText(tester, 'echo-score-$slot'), '0.00分 无评级');
    }
  });

  testWidgets('总览页输出副词条合计，暴击阈值超出部分不计入总分', (tester) async {
    await _pumpApp(tester);
    await _seedScoredFile(tester);

    final harness = _current!;
    final file = harness.workspace.activeFile!;
    harness.workspace.updateEcho(
      file.id,
      file
          .echoAt(0)
          .withTier(SubstatType.critRate, 3) // 7.5
          .withTier(SubstatType.critDmg, 8), // 21.0
    );
    harness.workspace.updateEcho(
      file.id,
      file.echoAt(1).withTier(SubstatType.critRate, 5), // 8.7
    );
    await tester.pumpAndSettle();

    // 合计：暴击率 7.5 + 8.7 = 16.2%，暴伤 21.0%。
    expect(find.text('暴击率 16.2%'), findsOneWidget);
    expect(find.text('暴击伤害 21.0%'), findsOneWidget);
    expect(find.text('攻击% 0.0%'), findsNothing);
    // 总分 = 7.5 + 21.0 + 8.7 = 37.20
    expect(_plainText(tester, 'total-score'), '37.20分 无评级');

    await tester.enterText(
      find.byKey(const ValueKey('crit-threshold')),
      '10.0',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('暴击率合计 16.2% 已超过阈值 10.0%'), findsOneWidget);
    expect(find.textContaining('超出的 6.2% 不计入总分'), findsOneWidget);
    // 37.2 − 6.2 × 1.0 = 31.0；单件声骸的评分不受阈值影响。
    expect(_plainText(tester, 'total-score'), '31.00分 无评级');
    expect(_plainText(tester, 'echo-score-0'), '28.50分 C级');
    expect(_plainText(tester, 'echo-score-1'), '8.70分 无评级');
    expect(harness.workspace.activeFile!.critThreshold, 10.0);

    // 清空阈值后恢复不设限的正常总分。
    await tester.enterText(find.byKey(const ValueKey('crit-threshold')), '');
    await tester.pumpAndSettle();
    expect(find.textContaining('已超过阈值'), findsNothing);
    expect(_plainText(tester, 'total-score'), '37.20分 无评级');
    expect(harness.workspace.activeFile!.critThreshold, isNull);
  });

  testWidgets('详情页实时输出当前评分与预期最高分', (tester) async {
    await _pumpApp(tester);
    await _seedScoredFile(tester);

    await tester.tap(find.byType(EchoCard).first);
    await tester.pumpAndSettle();
    expect(find.byType(EchoDetailPage), findsOneWidget);
    // 13 行都按「属性 系数值 × 档位」展示：系数只读，5 项为 1.000、其余 8 项 0.000。
    expect(find.text('×'), findsNWidgets(13));
    expect(find.text('1.000'), findsNWidgets(5));
    expect(find.text('0.000'), findsNWidgets(8));
    expect(_plainText(tester, 'current-score'), '0.00分 无评级');
    // 5 条全开在最优属性上 = 69.40，与理论最高分持平 → 满比值 ACE 级。
    expect(find.text('69.40分 ACE级'), findsOneWidget);
    expect(find.textContaining('剩余 5 条若都开在最优属性上'), findsOneWidget);

    await _selectTier(tester, 0, '3档 · 7.5% · 23.33%');

    expect(_plainText(tester, 'current-score'), '7.50分 无评级');
    // 当前 7.50 + 剩余 4 条最优（暴伤21.0+防御%14.7+攻击%11.6+生命%11.6=58.9）= 66.40，
    // 66.40/69.40 ≈ 0.957 → ACE 级。
    expect(find.text('66.40分 ACE级'), findsOneWidget);
    expect(find.textContaining('暴击伤害、防御%、攻击%、生命%'), findsOneWidget);
    expect(find.textContaining('已选 1/5'), findsOneWidget);
  });

  testWidgets('目标分数给出达成概率，不可能与必然的边界都正确', (tester) async {
    await _pumpApp(tester);
    await _seedScoredFile(tester);
    await tester.tap(find.byType(EchoCard).first);
    await tester.pumpAndSettle();
    await _selectTier(tester, 0, '3档 · 7.5% · 23.33%');

    // 当前 7.50，剩余 4 条最多再拿 58.9 → 上限 66.40，目标 67 不可能达成。
    await tester.enterText(
      find.byKey(const ValueKey('target-score-input')),
      '67',
    );
    await tester.pumpAndSettle();
    expect(find.text('0.00%'), findsOneWidget);

    // 目标不高于当前分：必然达成。
    await tester.enterText(
      find.byKey(const ValueKey('target-score-input')),
      '3',
    );
    await tester.pumpAndSettle();
    expect(find.text('100.00%'), findsOneWidget);

    // 清空目标分：不再显示概率。
    await tester.enterText(
      find.byKey(const ValueKey('target-score-input')),
      '',
    );
    await tester.pumpAndSettle();
    expect(find.text('填入目标分数后显示达成概率'), findsOneWidget);
  });

  testWidgets('非 0 档位超过 5 条时不输出结果并提示', (tester) async {
    final harness = await _pumpApp(tester);
    final file = await _seedScoredFile(tester);

    var echo = file.echoAt(0);
    for (final type in SubstatType.values.take(6)) {
      echo = echo.withTier(type, 1);
    }
    harness.workspace.updateEcho(file.id, echo);
    await tester.pumpAndSettle();

    expect(find.text('已输入 6 条词条，超过 5 条上限'), findsOneWidget);
    expect(find.textContaining('不计入总分'), findsOneWidget);
    expect(_plainText(tester, 'total-score'), '0.00分 无评级');

    await tester.tap(find.byType(EchoCard).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('不输出评分结果'), findsOneWidget);
    expect(find.byKey(const ValueKey('current-score')), findsNothing);
  });

  testWidgets('文件栏按文件名搜索过滤', (tester) async {
    await _pumpApp(tester);
    await _seedScoredFile(tester, fileName: '甲文件');
    await _seedScoredFile(tester, fileName: '乙文件', profileName: '守岸人');
    await tester.pumpAndSettle();
    expect(_panelFile('甲文件'), findsWidgets);
    expect(_panelFile('乙文件'), findsWidgets);

    await tester.enterText(_searchField(), '甲');
    await tester.pumpAndSettle();
    expect(_panelFile('甲文件'), findsWidgets);
    // 顶部工具栏始终显示当前文件（乙文件），因此只在文件栏范围内断言过滤结果。
    expect(_panelFile('乙文件'), findsNothing);

    await tester.enterText(_searchField(), '');
    await tester.pumpAndSettle();
    expect(_panelFile('乙文件'), findsWidgets);
  });

  testWidgets('只切换显示的文件不会提示保存', (tester) async {
    final harness = await _pumpApp(tester);
    await _seedScoredFile(tester, fileName: '甲文件');
    await _seedScoredFile(tester, fileName: '乙文件', profileName: '守岸人');
    await tester.pumpAndSettle();
    expect(harness.workspace.activeFile!.name, '乙文件');

    await tester.tap(find.text('甲文件').first);
    await tester.pumpAndSettle();

    expect(harness.workspace.activeFile!.name, '甲文件');
    expect(find.text('不保存'), findsNothing);
    expect(find.textContaining('角色：长离'), findsOneWidget);
  });

  testWidgets('关闭有改动的文件会提示保存，保存后文件关闭', (tester) async {
    final harness = await _pumpApp(tester);
    await _seedScoredFile(tester, fileName: '甲文件');
    final second = await _seedScoredFile(
      tester,
      fileName: '乙文件',
      profileName: '守岸人',
    );
    await tester.pumpAndSettle();

    harness.workspace.renameEcho(second.id, 0, '改了名字');
    await tester.pumpAndSettle();
    expect(find.byTooltip('有未保存的改动'), findsWidgets);

    await tester.tap(_fileMenuButton(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭文件').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('保存对「乙文件」的更改'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await _settle(tester);

    expect(harness.workspace.byId(second.id), isNull);
    expect(harness.workspace.activeFile!.name, '甲文件');
    expect(find.text('乙文件'), findsNothing);
  });

  testWidgets('关闭没有改动的文件不提示', (tester) async {
    final harness = await _pumpApp(tester);
    final file = await _seedScoredFile(tester, fileName: '甲文件');
    await _seedScoredFile(tester, fileName: '乙文件', profileName: '守岸人');
    await tester.pumpAndSettle();

    await tester.tap(_fileMenuButton(0)); // 乙文件，未改动
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭文件').last);
    await tester.pumpAndSettle();

    expect(find.text('不保存'), findsNothing);
    expect(harness.workspace.byId(file.id), isNotNull);
  });

  testWidgets('声骸卡片右上角的铅笔可以重命名', (tester) async {
    await _pumpApp(tester);
    await _seedScoredFile(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('重命名声骸').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '主声骸');
    // 总览页底部也有「重命名」按钮，这里只点对话框里的确认键（FilledButton）。
    await tester.tap(find.widgetWithText(FilledButton, '重命名'));
    await _settle(tester);

    expect(find.text('主声骸'), findsOneWidget);
    expect(find.text('声骸1'), findsNothing);
  });

  testWidgets('保存后未保存标记消失，且内容确实落盘', (tester) async {
    final harness = await _pumpApp(tester);
    final file = await _seedScoredFile(tester, fileName: '甲文件');
    await tester.pumpAndSettle();

    harness.workspace.renameEcho(file.id, 0, '改个名');
    await tester.pumpAndSettle();
    expect(find.byTooltip('有未保存的改动'), findsWidgets);
    expect(harness.workspace.hasUnsavedChanges, isTrue);

    await tester.tap(find.byTooltip('保存').first);
    await _settle(tester);

    expect(find.byTooltip('已保存'), findsWidgets);
    expect(harness.workspace.hasUnsavedChanges, isFalse);

    final reloaded = await harness.runAsync(() => harness.repository.loadAll());
    expect(reloaded!.items.single.echoes.first.name, '改个名');
  });

  testWidgets('窄屏时导航栏与文件栏收进抽屉', (tester) async {
    await _pumpApp(tester);
    await _seedScoredFile(tester);

    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();

    expect(find.byType(NavRail), findsNothing);
    expect(find.text('评分文件'), findsNothing);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.byType(NavRail), findsOneWidget);
    // 抽屉里 NavRail 的导航项与文件栏标题都叫「评分文件」，只在 NavRail 内断言。
    expect(
      find.descendant(of: find.byType(NavRail), matching: find.text('评分文件')),
      findsOneWidget,
    );
    expect(find.text('编辑角色系数'), findsOneWidget);
    expect(find.text('GitHub 仓库'), findsOneWidget);
  });

  testWidgets('主题设置页提供自定义背景图入口，默认无背景时恢复按钮禁用', (tester) async {
    final harness = await _pumpApp(tester);
    harness.workspace.show(ShellView.theme);
    await tester.pumpAndSettle();

    expect(find.text('自定义背景图'), findsOneWidget);
    expect(find.text('导入图片'), findsOneWidget);
    expect(find.text('当前：默认背景'), findsOneWidget);

    // 没有背景图时「恢复默认背景」应禁用，且不渲染任何背景图。
    final restore = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '恢复默认背景'),
    );
    expect(restore.onPressed, isNull);
    expect(find.byType(Image), findsNothing);
  });
}

// ------------------------------------------------------------------ 测试脚手架

class _Harness {
  _Harness({
    required this.root,
    required this.scope,
    required this.settings,
    required this.profiles,
    required this.workspace,
    required this.repository,
    required this.tester,
  });

  final Directory root;
  final AppScope scope;
  final SettingsController settings;
  final ProfileController profiles;
  final WorkspaceController workspace;
  final ScoreRepository repository;
  final WidgetTester tester;

  /// 真实文件 IO 必须在 `runAsync` 里执行，否则会被测试的假异步区卡住。
  Future<T?> runAsync<T>(Future<T> Function() body) => tester.runAsync(body);
}

_Harness? _current;

Future<_Harness> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 960);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final harness = await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final root = await Directory.systemTemp.createTemp('echo_scorer_test');
    final settings = SettingsController(preferences);
    final storage = StorageService(root);
    await storage.ensureStructure();
    final repository = ScoreRepository(storage);
    final profiles = ProfileController(ProfileRepository(storage));
    final workspace = WorkspaceController(
      repository,
      storage,
      settings.repository,
    );
    final background = BackgroundImageService(
      Directory(p.join(root.path, 'background')),
    );
    final scope = AppScope(
      storage: storage,
      settings: settings,
      profiles: profiles,
      workspace: workspace,
      background: background,
    );
    await profiles.reload();
    await workspace.bootstrap();
    return _Harness(
      root: root,
      scope: scope,
      settings: settings,
      profiles: profiles,
      workspace: workspace,
      repository: repository,
      tester: tester,
    );
  });

  final result = harness!;
  _current = result;
  addTearDown(() async {
    _current = null;
    await tester.runAsync(() async {
      if (await result.root.exists()) {
        await result.root.delete(recursive: true);
      }
    });
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AppScope>.value(value: result.scope),
        ChangeNotifierProvider<SettingsController>.value(
          value: result.settings,
        ),
        ChangeNotifierProvider<ProfileController>.value(value: result.profiles),
        ChangeNotifierProvider<WorkspaceController>.value(
          value: result.workspace,
        ),
      ],
      child: const EchoScorerApp(),
    ),
  );
  await tester.pumpAndSettle();
  return result;
}

/// 建一份带角色系数快照、已落盘的评分文件并打开。
Future<ScoreFile> _seedScoredFile(
  WidgetTester tester, {
  String fileName = '测试文件',
  String profileName = '长离',
}) async {
  final harness = _current!;
  final file = (await tester.runAsync(() async {
    final created = await harness.profiles.create(profileName);
    final profile = await harness.profiles.save(
      created.copyWith(coefficients: _fiveCoefficients),
    );
    final newFile = await harness.workspace.createFile(fileName);
    await harness.workspace.saveFile(newFile.applyingProfile(profile));
    return harness.workspace.activeFile;
  }))!;
  await tester.pumpAndSettle();
  return file;
}

/// 让真实 IO 完成、界面刷新，并把 SnackBar 的自动关闭计时器走完。
///
/// 点击处理里的 `await`（保存=解析文件夹+原子写+重扫、选角色=重扫、关闭=保存+关闭）
/// 运行在测试的假异步区。一次保存会链式地触发十来次真实磁盘 IO（`ScoreRepository.save`
/// 里 `exists`/`readJson`/`writeJsonAtomic`，加上 `loadAll` 逐个文件 `list`+读），
/// 每一步的续体都要「runAsync 放行真实事件循环 + pump 驱动续体」才能推进一格，
/// 因此这里循环足够多轮，直到整条 IO 链跑完。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pumpAndSettle();
  }
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

Future<void> _selectTier(
  WidgetTester tester,
  int rowIndex,
  String itemLabel,
) async {
  await tester.tap(find.byType(DropdownButton<int>).at(rowIndex));
  await tester.pumpAndSettle();
  await tester.tap(find.text(itemLabel).last);
  await tester.pumpAndSettle();
}

Finder _searchField() => find.descendant(
  of: find.byType(FilePanel),
  matching: find.byType(TextField),
);

/// 文件栏范围内的文件名文本（顶部工具栏也会显示当前文件名，需区分开）。
Finder _panelFile(String name) =>
    find.descendant(of: find.byType(FilePanel), matching: find.text(name));

Finder _fileMenuButton(int index) => find
    .descendant(
      of: find.byType(FilePanel),
      matching: find.byType(PopupMenuButton<String>),
    )
    .at(index);

/// 读取带 key 的富文本（分数与评级用 TextSpan 拼成，`find.text` 抓不到）。
String _plainText(WidgetTester tester, String keyValue) {
  final finder = find.descendant(
    of: find.byKey(ValueKey(keyValue)),
    matching: find.byType(RichText),
  );
  return tester.widget<RichText>(finder.first).text.toPlainText();
}
