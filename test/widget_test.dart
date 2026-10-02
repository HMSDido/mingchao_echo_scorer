import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/app.dart';
import 'package:mingchao_echo_scorer/data/catalog/substat_type.dart';
import 'package:mingchao_echo_scorer/data/models/coefficients.dart';
import 'package:mingchao_echo_scorer/data/models/score_file.dart';
import 'package:mingchao_echo_scorer/data/models/share_link.dart';
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
import 'package:mingchao_echo_scorer/ui/shell/file_list_page.dart';
import 'package:mingchao_echo_scorer/ui/shell/file_panel.dart';
import 'package:mingchao_echo_scorer/ui/shell/nav_rail.dart';
import 'package:mingchao_echo_scorer/ui/shell/top_toolbar.dart';
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

  testWidgets('页首「更换系数」换一份快照，改动被脏检查认出', (tester) async {
    final harness = await _pumpApp(tester);
    await harness.runAsync(() async {
      final changli = await harness.profiles.create('长离');
      await harness.profiles.save(
        changli.copyWith(coefficients: _fiveCoefficients),
      );
      final shou = await harness.profiles.create('21守岸人');
      await harness.profiles.save(
        shou.copyWith(coefficients: {SubstatType.critDmg: 2.0}),
      );
      await harness.workspace.createFile('测试文件');
    });
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '选择角色'));
    await _settle(tester);
    await tester.tap(find.text('长离').last);
    await _settle(tester);
    await harness.runAsync(
      () => harness.workspace.saveFile(harness.workspace.activeFile!),
    );
    await tester.pumpAndSettle();
    expect(harness.workspace.isDirty(harness.workspace.activeFile!), isFalse);

    // 入口在页首、贴着当前系数名；页脚不再重复放一个。
    expect(find.byKey(const ValueKey('swap-profile')), findsOneWidget);
    expect(find.text('更换角色'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap-profile')));
    // 更换系数前会先 reload() 重扫配置，这是真实 IO，得用 _settle 放行。
    await _settle(tester);
    expect(find.text('更换角色系数配置'), findsOneWidget);
    await tester.tap(find.text('21守岸人').last);
    await _settle(tester);

    final file = harness.workspace.activeFile!;
    expect(file.profileName, '21守岸人');
    // 系数整体换成新快照，并按新系数重算。
    expect(file.coefficients[SubstatType.critRate], 0.0);
    expect(file.coefficients[SubstatType.critDmg], 2.0);
    expect(find.textContaining('理论最高 210.00分'), findsOneWidget);
    // 切换算内容改动：未保存状态要能被脏检查认出。
    expect(harness.workspace.isDirty(file), isTrue);
  });

  testWidgets('「选择角色」弹窗按分组显示：组头默认折叠，点开才能选', (tester) async {
    final harness = await _pumpApp(tester);
    final grouped = (await harness.runAsync(
      () => harness.profiles.create('01长离'),
    ))!;
    await harness.runAsync(() => harness.profiles.create('组外配置'));
    expect(harness.profiles.addLayoutGroup('绯雪'), isTrue);
    harness.profiles.placeInLayoutGroup('绯雪', grouped.id);
    // 组内放入会自动展开；先收起，才能区分弹窗展开态与列表展开态。
    harness.profiles.toggleLayoutGroup('绯雪');
    await harness.runAsync(() => harness.workspace.createFile('测试文件'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '选择角色'));
    await _settle(tester);
    expect(find.text('选择角色'), findsWidgets);

    // 组标题可见但不可选；收起的组里条目不显示，根层条目照常显示。
    expect(find.text('绯雪'), findsOneWidget);
    expect(find.text('01长离'), findsNothing);
    expect(find.text('组外配置'), findsOneWidget);

    await tester.tap(find.text('绯雪'));
    await tester.pumpAndSettle();
    expect(find.text('01长离'), findsOneWidget);

    await tester.tap(find.text('01长离'));
    await _settle(tester);
    expect(harness.workspace.activeFile!.profileName, '01长离');

    // 弹窗的展开态只活在本次会话：不写 prefs，列表页的折叠不受影响。
    expect(harness.settings.repository.profileExpandedGroups, isEmpty);
    await _dismissSnackBars(tester);
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

  testWidgets('详情页「全词条置 0」一键清空该声骸全部档位', (tester) async {
    final harness = await _pumpApp(tester);
    final file = await _seedScoredFile(tester);
    harness.workspace.updateEcho(
      file.id,
      file
          .echoAt(0)
          .withTier(SubstatType.critRate, 3)
          .withTier(SubstatType.critDmg, 2),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(EchoCard).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('已选 2/5'), findsOneWidget);
    expect(_plainText(tester, 'current-score'), isNot(startsWith('0.00')));

    await tester.tap(find.byTooltip('全词条置 0'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已选 0/5'), findsOneWidget);
    expect(find.textContaining('已选词条'), findsNothing);
    expect(_plainText(tester, 'current-score'), '0.00分 无评级');
    // 没有档位可清后，按钮置灰。
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.clear_all),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    // 置 0 算内容改动：写回草稿后该声骸档位为空。
    await tester.tap(find.widgetWithText(FilledButton, '保存本声骸'));
    await tester.pumpAndSettle();
    expect(harness.workspace.byId(file.id)!.echoAt(0).tiers, isEmpty);
    await _dismissSnackBars(tester);
  });

  testWidgets('窄屏详情页渲染词条行，点档位标签即可输入', (tester) async {
    await _pumpApp(tester);
    await _seedScoredFile(tester);

    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(EchoCard).first);
    await tester.pumpAndSettle();

    expect(find.byType(EchoDetailPage), findsOneWidget);
    // 13 行词条与档位标签都要渲染出来（曾因内层 ListView 拿到无界高度整页空白）。
    expect(find.text('暴击率'), findsOneWidget);
    expect(find.textContaining('已选 0/5'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '3档 7.5%').first);
    await tester.pumpAndSettle();

    expect(_plainText(tester, 'current-score'), '7.50分 无评级');
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

  testWidgets('窄屏收起侧栏与功能栏，标签页按钮打开全屏文件列表', (tester) async {
    final harness = await _pumpApp(tester);
    await _seedScoredFile(tester);

    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();

    expect(find.byType(NavRail), findsNothing);
    expect(find.byType(FilePanel), findsNothing);
    expect(find.byType(TopToolbar), findsNothing);
    // 顶栏标题换成当前文件名，正文仍是总览页。
    expect(find.text('测试文件'), findsOneWidget);
    expect(find.byType(EchoCard), findsNWidgets(5));

    await tester.tap(find.byTooltip('标签页'));
    await tester.pumpAndSettle();

    final list = find.byType(FileListPage);
    expect(list, findsOneWidget);
    expect(
      find.descendant(of: list, matching: find.text('测试文件')),
      findsOneWidget,
    );
    // 行尾直接给分享 / 重命名 / 删除三个常用操作。
    expect(
      find.descendant(of: list, matching: find.byTooltip('复制分享链接')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: list, matching: find.byTooltip('重命名')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: list, matching: find.byTooltip('删除')),
      findsOneWidget,
    );

    // 点一行切到该文件并返回列表。
    await tester.tap(find.descendant(of: list, matching: find.text('测试文件')));
    await tester.pumpAndSettle();

    expect(find.byType(FileListPage), findsNothing);
    expect(harness.workspace.activeFile!.name, '测试文件');

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.byType(NavRail), findsOneWidget);
    // 抽屉里只放导航，不再塞文件栏。
    expect(find.byType(FilePanel), findsNothing);
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

  testWidgets('复制全部配置到剪贴板，清空后粘贴导入可原样恢复', (tester) async {
    final harness = await _pumpApp(tester);
    _mockClipboard(tester);

    // 三份中文名配置，各自只有一项系数非 0，便于验证内容真的被搬过去了。
    await harness.runAsync(() async {
      for (final (name, coefficients) in [
        ('01长离', {SubstatType.critRate: 1.0}),
        ('21守岸人', {SubstatType.critDmg: 0.9}),
        ('卡卡罗', {SubstatType.atkPct: 0.75}),
      ]) {
        final created = await harness.profiles.create(name);
        await harness.profiles.save(
          created.copyWith(coefficients: coefficients),
        );
      }
    });

    harness.workspace.show(ShellView.profiles);
    await tester.pumpAndSettle();
    expect(find.text('01长离'), findsOneWidget);

    await _openProfilesMenu(tester, '复制全部配置到剪贴板');
    await _settle(tester, dismissSnack: false);
    expect(find.text('已复制 3 个配置到剪贴板'), findsOneWidget);
    await _dismissSnackBars(tester);

    // 剪贴板里是「说明头 + 链接」成对的多行文本，配置内容不以明文出现。
    final clipboard = await harness.runAsync(
      () => Clipboard.getData(Clipboard.kTextPlain),
    );
    final lines = clipboard!.text!.split('\n');
    expect(lines, hasLength(6));
    expect(
      lines.where((line) => line.startsWith('#')),
      containsAll(['# 01长离系数配置', '# 21守岸人系数配置', '# 卡卡罗系数配置']),
    );
    expect(
      lines
          .where((line) => !line.startsWith('#'))
          .every((line) => line.startsWith('echoscorer://')),
      isTrue,
    );
    expect(clipboard.text, isNot(contains('"coefficients"')));

    // 清空列表，模拟换到一台没有任何配置的设备。
    await harness.runAsync(() async {
      for (final profile in List.of(harness.profiles.profiles)) {
        await harness.profiles.delete(profile.id);
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('还没有角色系数配置'), findsOneWidget);

    await _openProfilesMenu(tester, '从剪贴板导入配置');
    await _settleUntil(tester, () => harness.profiles.profiles.length == 3);

    expect(find.text('成功导入 3 个配置'), findsOneWidget);
    expect(find.text('01长离'), findsOneWidget);
    expect(find.text('21守岸人'), findsOneWidget);
    expect(find.text('卡卡罗'), findsOneWidget);
    expect(find.textContaining('已设置 1/13 项'), findsNWidgets(3));
    expect(
      harness.profiles.profiles
          .firstWhere((profile) => profile.name == '01长离')
          .coefficients[SubstatType.critRate],
      1.0,
    );
    await _dismissSnackBars(tester);
  });

  testWidgets('剪贴板里混着无效内容时，跳过坏行并列出原因', (tester) async {
    final harness = await _pumpApp(tester);
    final created = await harness.runAsync(() => harness.profiles.create('长离'));
    _mockClipboard(tester, initial: '${ProfileShare.encode(created!)}\n不是配置');

    harness.workspace.show(ShellView.profiles);
    await tester.pumpAndSettle();

    await _openProfilesMenu(tester, '从剪贴板导入配置');
    await _settleUntil(tester, () => harness.profiles.profiles.length == 2);

    expect(find.text('成功导入 1 个配置，跳过 1 行无效数据'), findsOneWidget);
    expect(find.textContaining('第 3 行'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '知道了'));
    await tester.pumpAndSettle();
    expect(find.text('长离'), findsWidgets);
  });

  testWidgets('评分文件复制分享链接，删除后粘贴导入可原样恢复', (tester) async {
    final harness = await _pumpApp(tester);
    _mockClipboard(tester);
    final file = await _seedScoredFile(tester, fileName: '长离-主C');

    // 录一条档位再落盘，恢复后要能看出内容真的被搬回来了。
    final saved = (await harness.runAsync(() async {
      harness.workspace.updateEcho(
        file.id,
        file.echoAt(0).withTier(SubstatType.critRate, 4),
      );
      await harness.workspace.saveFile(harness.workspace.activeFile!);
      return harness.workspace.activeFile;
    }))!;
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('复制链接').first);
    await _settle(tester, dismissSnack: false);
    expect(find.text('已复制「长离-主C」的分享链接'), findsOneWidget);
    await _dismissSnackBars(tester);

    final clipboard = await harness.runAsync(
      () => Clipboard.getData(Clipboard.kTextPlain),
    );
    expect(clipboard!.text, startsWith('# 长离-主C评分文件\nechoscorer://'));
    expect(clipboard.text, isNot(contains('"echoes"')));

    // 删掉本地文件，模拟换到一台什么都没有的设备。
    await harness.runAsync(
      () => harness.workspace.deleteFile(harness.workspace.activeFile!),
    );
    await tester.pumpAndSettle();
    expect(harness.workspace.openFiles, isEmpty);
    expect(find.text('长离-主C'), findsNothing);

    await tester.tap(find.byTooltip('粘贴导入').first);
    await _settleUntil(
      tester,
      () => harness.workspace.openFiles.any((item) => item.name == '长离-主C'),
    );

    expect(find.text('成功导入 1 个评分文件'), findsOneWidget);
    final restored = harness.workspace.activeFile!;
    expect(restored.name, saved.name);
    expect(restored.profileName, saved.profileName);
    expect(restored.coefficients, saved.coefficients);
    expect(restored.echoAt(0).tierOf(SubstatType.critRate), 4);
    expect(restored.echoAt(0).sameContentAs(saved.echoAt(0)), isTrue);
    expect(harness.workspace.isDirty(restored), isFalse);
    await _dismissSnackBars(tester);
  });

  testWidgets('标签页批量导出全部已打开文件，关闭后整批粘贴导入', (tester) async {
    final harness = await _pumpApp(tester);
    _mockClipboard(tester);
    final first = await _seedScoredFile(tester, fileName: '甲文件');
    await _seedScoredFile(tester, fileName: '乙文件');

    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('标签页'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制全部分享链接'));
    await _settle(tester, dismissSnack: false);
    expect(find.text('已复制 2 个评分文件的分享链接'), findsOneWidget);
    await _dismissSnackBars(tester);

    // 剪贴板里是「说明头 + 链接」成对的多行文本，文件名出现在说明头里。
    final clipboard = await harness.runAsync(
      () => Clipboard.getData(Clipboard.kTextPlain),
    );
    final lines = clipboard!.text!.split('\n');
    expect(lines, hasLength(4));
    expect(
      lines.where((line) => line.startsWith('#')),
      containsAll(['# 甲文件评分文件', '# 乙文件评分文件']),
    );
    expect(
      lines
          .where((line) => !line.startsWith('#'))
          .every((line) => line.startsWith('echoscorer://')),
      isTrue,
    );
    expect(clipboard.text, isNot(contains('"echoes"')));

    // 删掉全部文件（含磁盘），模拟换到一台什么都没有的设备后整批导入。
    await harness.runAsync(() async {
      for (final file in List.of(harness.workspace.openFiles)) {
        await harness.workspace.deleteFile(file);
      }
    });
    await tester.pumpAndSettle();
    expect(harness.workspace.openFiles, isEmpty);

    await tester.tap(find.byTooltip('更多操作').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('粘贴导入'));
    await _settleUntil(tester, () => harness.workspace.openFiles.length == 2);

    expect(find.text('成功导入 2 个评分文件'), findsOneWidget);
    expect(
      harness.workspace.openFiles.map((file) => file.name).toSet(),
      containsAll(<String>['甲文件', '乙文件']),
    );
    final restored = harness.workspace.byId(first.id);
    expect(restored, isNotNull);
    expect(harness.workspace.isDirty(restored!), isFalse);
    await _dismissSnackBars(tester);
  });

  testWidgets('标签页批量删除勾选的评分文件，磁盘上一并移除', (tester) async {
    final harness = await _pumpApp(tester);
    await _seedScoredFile(tester, fileName: '保留文件');
    await _seedScoredFile(tester, fileName: '甲文件');
    await _seedScoredFile(tester, fileName: '乙文件');

    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('标签页'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量删除'));
    await tester.pumpAndSettle();

    // 一项都没勾时「删除」不可点，勾两项后计数跟着变。
    expect(find.text('已选 0 项'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '删除'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, '甲文件'));
    await tester.tap(find.widgetWithText(CheckboxListTile, '乙文件'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _settleUntil(
      tester,
      () => find.text('已删除 2 个评分文件').evaluate().isNotEmpty,
    );

    expect(find.text('已删除 2 个评分文件'), findsOneWidget);
    expect(harness.workspace.openFiles.single.name, '保留文件');
    // 列表页还开着，剩下的那一条仍在。
    expect(
      find.descendant(
        of: find.byType(FileListPage),
        matching: find.text('保留文件'),
      ),
      findsOneWidget,
    );

    // 磁盘上的文件夹真的没了，不只是从内存列表里摘掉。
    await harness.runAsync(() => harness.workspace.refreshDisk());
    await tester.pumpAndSettle();
    expect(
      harness.workspace.diskFiles.map((file) => file.name).toList(),
      <String>['保留文件'],
    );
    await _dismissSnackBars(tester);
  });

  testWidgets('标签页批量导出：勾选的文件链接各带名字说明头', (tester) async {
    final harness = await _pumpApp(tester);
    _mockClipboard(tester);
    await _seedScoredFile(tester, fileName: '甲文件');
    await _seedScoredFile(tester, fileName: '乙文件');

    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('标签页'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量导出'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(CheckboxListTile, '甲文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '导出'));
    await _settle(tester, dismissSnack: false);

    expect(find.text('已复制 1 个评分文件的分享链接'), findsOneWidget);
    await _dismissSnackBars(tester);

    final clipboard = await harness.runAsync(
      () => Clipboard.getData(Clipboard.kTextPlain),
    );
    final lines = clipboard!.text!.split('\n');
    expect(lines, hasLength(2));
    expect(lines.first, '# 甲文件评分文件');
    expect(lines[1], startsWith('echoscorer://'));
  });

  testWidgets('文件栏组菜单导出本组，一次复制组内全部链接', (tester) async {
    final harness = await _pumpApp(tester);
    _mockClipboard(tester);
    final a = (await harness.runAsync(
      () => harness.workspace.createFile('甲文件'),
    ))!;
    final b = (await harness.runAsync(
      () => harness.workspace.createFile('乙文件'),
    ))!;
    await harness.runAsync(() => harness.workspace.createFile('组外文件'));
    expect(harness.workspace.addLayoutGroup('日常'), isTrue);
    harness.workspace.placeInLayoutGroup('日常', a.id);
    harness.workspace.placeInLayoutGroup('日常', b.id);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(FilePanel),
        matching: find.byKey(const ValueKey('file-group-menu-日常')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出本组'));
    await _settle(tester, dismissSnack: false);

    expect(find.text('已复制分组「日常」的 2 个分享链接'), findsOneWidget);
    await _dismissSnackBars(tester);

    final clipboard = await harness.runAsync(
      () => Clipboard.getData(Clipboard.kTextPlain),
    );
    final lines = clipboard!.text!.split('\n');
    expect(lines, hasLength(4));
    expect(
      lines.where((line) => line.startsWith('#')),
      containsAll(<String>['# 甲文件评分文件', '# 乙文件评分文件']),
    );
    expect(lines, isNot(contains('# 组外文件评分文件')));
  });

  testWidgets('分组默认折叠：收起只见组名与数量，点组头展开', (tester) async {
    final harness = await _pumpApp(tester);
    final a = (await harness.runAsync(
      () => harness.workspace.createFile('甲文件'),
    ))!;
    final b = (await harness.runAsync(
      () => harness.workspace.createFile('乙文件'),
    ))!;
    expect(harness.workspace.addLayoutGroup('日常'), isTrue);
    harness.workspace.placeInLayoutGroup('日常', a.id);
    harness.workspace.placeInLayoutGroup('日常', b.id);
    await tester.pumpAndSettle();
    // 组内新建/放入后自动展开，保证用户看得见结果。
    expect(harness.workspace.isGroupExpanded('日常'), isTrue);
    expect(_panelFile('甲文件'), findsOneWidget);

    // 点组头收起：条目消失，组名和数量仍在。
    await tester.tap(
      find.descendant(of: find.byType(FilePanel), matching: find.text('日常')),
    );
    await tester.pumpAndSettle();
    expect(_panelFile('甲文件'), findsNothing);
    expect(_panelFile('乙文件'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(FilePanel),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsOneWidget,
    );
    expect(
      harness.settings.repository.scoreExpandedGroups,
      isNot(contains('日常')),
    );

    // 再点展开。
    await tester.tap(
      find.descendant(of: find.byType(FilePanel), matching: find.text('日常')),
    );
    await tester.pumpAndSettle();
    expect(_panelFile('甲文件'), findsOneWidget);
    expect(harness.settings.repository.scoreExpandedGroups, contains('日常'));

    // 收起态的组仍统计完整成员数（2 而非可见行数 0）。
    harness.workspace.toggleLayoutGroup('日常');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(FilePanel), matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('配置页 ⋮ 菜单收拢导入导出，并能批量删除勾选的配置', (tester) async {
    final harness = await _pumpApp(tester);
    await harness.runAsync(() async {
      for (final name in ['01长离', '21守岸人', '卡卡罗']) {
        await harness.profiles.create(name);
      }
    });

    harness.workspace.show(ShellView.profiles);
    await tester.pumpAndSettle();

    // 原来的两个图标按钮收进 ⋮，菜单项改用文字描述。
    expect(find.byTooltip('从剪贴板导入配置'), findsNothing);
    expect(find.byTooltip('复制全部配置到剪贴板'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('profiles-menu')));
    await tester.pumpAndSettle();
    expect(find.text('从剪贴板导入配置'), findsOneWidget);
    expect(find.text('复制全部配置到剪贴板'), findsOneWidget);

    await tester.tap(find.text('批量删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '01长离'));
    await tester.tap(find.widgetWithText(CheckboxListTile, '卡卡罗'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _settleUntil(tester, () => harness.profiles.profiles.length == 1);
    await _drainSnack(tester);

    expect(find.text('已删除 2 个配置'), findsOneWidget);
    expect(harness.profiles.profiles.single.name, '21守岸人');
    expect(find.text('01长离'), findsNothing);
    expect(find.text('卡卡罗'), findsNothing);
    await _dismissSnackBars(tester);
  });

  testWidgets('配置页新建分组，拖把手把配置移进组，布局落进 prefs', (tester) async {
    final harness = await _pumpApp(tester);
    await harness.runAsync(() async {
      await harness.profiles.create('01长离');
      await harness.profiles.create('21守岸人');
    });

    harness.workspace.show(ShellView.profiles);
    await tester.pumpAndSettle();

    await _openProfilesMenu(tester, '新建分组');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '绯雪',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '新建'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('绯雪'), findsOneWidget);

    // 第一行配置的把手一路拖到列表末尾：越过组标题，落进「绯雪」组内。
    final firstRowId = harness.profiles.profiles.first.id;
    await tester.drag(
      find.byIcon(Icons.drag_indicator).first,
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();

    expect(harness.profiles.layoutGroupMemberIds('绯雪'), [firstRowId]);
    expect(harness.settings.repository.profileLayoutTokens, contains('g:绯雪'));
  });

  testWidgets('组内新建的配置直接落在该组组头下', (tester) async {
    final harness = await _pumpApp(tester);
    expect(harness.profiles.addLayoutGroup('绯雪'), isTrue);

    harness.workspace.show(ShellView.profiles);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('group-menu-绯雪')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('在组内新建配置'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '01绯雪',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '新建'),
      ),
    );
    await _settleUntil(tester, () => harness.profiles.profiles.length == 1);

    // 新建后会打开编辑器，退出编辑器回到列表。
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    expect(harness.profiles.layoutGroupMemberIds('绯雪'), hasLength(1));
    expect(find.text('1 个'), findsOneWidget);
    expect(find.text('01绯雪'), findsOneWidget);
    await _dismissSnackBars(tester);
  });

  testWidgets('清空分组删除组内配置，但分组本身保留', (tester) async {
    final harness = await _pumpApp(tester);
    final created = (await harness.runAsync(
      () => harness.profiles.create('01长离'),
    ))!;
    expect(harness.profiles.addLayoutGroup('绯雪'), isTrue);
    harness.profiles.placeInLayoutGroup('绯雪', created.id);

    harness.workspace.show(ShellView.profiles);
    await tester.pumpAndSettle();
    expect(find.text('1 个'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('group-menu-绯雪')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空分组（删配置）'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await _settleUntil(tester, () => harness.profiles.profiles.isEmpty);

    expect(find.text('绯雪'), findsOneWidget);
    expect(find.text('0 个'), findsOneWidget);
    expect(find.text('01长离'), findsNothing);
    await _dismissSnackBars(tester);
  });

  testWidgets('删除分组只删标题，组内配置释放回根层不被动', (tester) async {
    final harness = await _pumpApp(tester);
    final created = (await harness.runAsync(
      () => harness.profiles.create('01长离'),
    ))!;
    expect(harness.profiles.addLayoutGroup('绯雪'), isTrue);
    harness.profiles.placeInLayoutGroup('绯雪', created.id);

    harness.workspace.show(ShellView.profiles);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('group-menu-绯雪')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分组（留配置）'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除分组'));
    await tester.pumpAndSettle();

    expect(find.text('绯雪'), findsNothing);
    expect(harness.profiles.layoutRows.any((row) => row.isGroup), isFalse);
    expect(harness.profiles.profiles, hasLength(1));
    expect(find.text('01长离'), findsOneWidget);
    await _dismissSnackBars(tester);
  });

  testWidgets('文件栏新建分组，拖把手把评分文件移进组，布局落进 prefs', (tester) async {
    final harness = await _pumpApp(tester);
    await harness.runAsync(() async {
      await harness.workspace.createFile('甲文件');
      await harness.workspace.createFile('乙文件');
    });
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建分组'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '日常',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '新建'),
      ),
    );
    await tester.pumpAndSettle();

    final panel = find.byType(FilePanel);
    expect(
      find.descendant(of: panel, matching: find.text('日常')),
      findsOneWidget,
    );

    // 第一行文件的把手一路拖到列表末尾：越过组标题，落进「日常」组。
    final firstId = harness.workspace.openFiles.first.id;
    final grip = find
        .descendant(of: panel, matching: find.byIcon(Icons.drag_indicator))
        .first;
    final gesture = await tester.startGesture(tester.getCenter(grip));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(harness.workspace.layoutGroupMemberIds('日常'), [firstId]);
    expect(harness.settings.repository.scoreLayoutTokens, contains('g:日常'));
  });

  testWidgets('删除评分文件分组只删标题，文件释放回根层不被动', (tester) async {
    final harness = await _pumpApp(tester);
    final created = (await harness.runAsync(
      () => harness.workspace.createFile('甲文件'),
    ))!;
    expect(harness.workspace.addLayoutGroup('日常'), isTrue);
    harness.workspace.placeInLayoutGroup('日常', created.id);

    await tester.pumpAndSettle();
    final panel = find.byType(FilePanel);
    await tester.tap(
      find.descendant(
        of: panel,
        matching: find.byKey(const ValueKey('file-group-menu-日常')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分组（留文件）'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除分组'));
    await tester.pumpAndSettle();

    expect(find.descendant(of: panel, matching: find.text('日常')), findsNothing);
    expect(harness.workspace.openFiles, hasLength(1));
    expect(
      find.descendant(of: panel, matching: find.text('甲文件')),
      findsOneWidget,
    );
    await _dismissSnackBars(tester);
  });

  testWidgets('窄屏标签页列表同样分组，拖出组标题即回到根层', (tester) async {
    final harness = await _pumpApp(tester);
    final created = (await harness.runAsync(
      () => harness.workspace.createFile('窄屏文件'),
    ))!;
    expect(harness.workspace.addLayoutGroup('标签组'), isTrue);
    harness.workspace.placeInLayoutGroup('标签组', created.id);

    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('标签页'));
    await tester.pumpAndSettle();

    final list = find.byType(FileListPage);
    expect(
      find.descendant(of: list, matching: find.text('标签组')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: list, matching: find.text('1 个')),
      findsOneWidget,
    );

    // 文件行的把手拖到组标题之上：回到根层，组里没成员了。
    await tester.drag(
      find
          .descendant(of: list, matching: find.byIcon(Icons.drag_indicator))
          .last,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(harness.workspace.layoutGroupMemberIds('标签组'), isEmpty);
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
    final profiles = ProfileController(
      ProfileRepository(storage),
      layoutStore: settings.repository,
    );
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

/// 打开「编辑角色系数」页头部的 ⋮ 菜单并点其中一项。
Future<void> _openProfilesMenu(WidgetTester tester, String item) async {
  await tester.tap(find.byKey(const ValueKey('profiles-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pump();
}

/// 让真实 IO 完成、界面刷新，并把 SnackBar 的自动关闭计时器走完。
///
/// 点击处理里的 `await`（保存=解析文件夹+原子写+重扫、选角色=重扫、关闭=保存+关闭）
/// 运行在测试的假异步区。一次保存会链式地触发十来次真实磁盘 IO（`ScoreRepository.save`
/// 里 `exists`/`readJson`/`writeJsonAtomic`，加上 `loadAll` 逐个文件 `list`+读），
/// 每一步的续体都要「runAsync 放行真实事件循环 + pump 驱动续体」才能推进一格，
/// 因此这里循环足够多轮，直到整条 IO 链跑完。
Future<void> _settle(WidgetTester tester, {bool dismissSnack = true}) async {
  for (var i = 0; i < 24; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pumpAndSettle();
  }
  if (dismissSnack) await _dismissSnackBars(tester);
}

/// 一直推进到 [until] 成立，而不是固定轮数。
///
/// 批量导入的真实 IO 链比单次保存长得多，固定轮数要么不够、要么多跑到把
/// SnackBar 的 3 秒自动关闭计时器走完（`pumpAndSettle` 每次推进 100ms 假时间），
/// 导致「刚弹出的提示」在断言前就消失了。
Future<void> _settleUntil(WidgetTester tester, bool Function() until) async {
  for (var i = 0; i < 200 && !until(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pumpAndSettle();
  }
  expect(until(), isTrue, reason: '条件在 200 轮内没有达成');
}

/// 把 SnackBar 的 3 秒自动关闭计时器走完，避免它挡住后续断言。
Future<void> _dismissSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

/// 只放行真实事件循环 + 少量假时间，让「控制器已 notify → 动作续体弹提示」跑完。
///
/// `_settleUntil` 的条件在控制器 notify 的那一刻就成立了，可提示是紧接着的续体里
/// 才弹的；用 `_settle` 补跑又会把假时钟推过 3 秒，提示自己先消失了。
Future<void> _drainSnack(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// flutter_test 没有内置剪贴板 mock，这里接住 `flutter/platform` 频道上的两个
/// Clipboard 方法，让「复制 / 粘贴导入」在测试里真的能往返。
void _mockClipboard(WidgetTester tester, {String initial = ''}) {
  var stored = initial;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          stored = (call.arguments as Map)['text'] as String? ?? '';
        case 'Clipboard.getData':
          return <String, dynamic>{'text': stored};
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
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
