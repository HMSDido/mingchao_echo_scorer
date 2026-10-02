import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/data/catalog/substat_type.dart';
import 'package:mingchao_echo_scorer/data/models/coefficient_profile.dart';
import 'package:mingchao_echo_scorer/data/models/echo_entry.dart';
import 'package:mingchao_echo_scorer/data/models/score_file.dart';
import 'package:mingchao_echo_scorer/data/repositories/score_repository.dart';
import 'package:mingchao_echo_scorer/data/repositories/storage_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;
  late StorageService storage;
  late ScoreRepository repository;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('echo_scorer_score');
    storage = StorageService(tempRoot);
    await storage.ensureStructure();
    repository = ScoreRepository(storage);
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  CoefficientProfile profile(String name) =>
      CoefficientProfile.create(name).copyWith(
        coefficients: {
          SubstatType.critRate: 1.0,
          SubstatType.critDmg: 1.0,
          SubstatType.atkPct: 0.75,
          SubstatType.energyRegen: 0.5,
        },
      );

  ScoreFile sample(String name) =>
      ScoreFile.fromProfile(name: name, profile: profile('长离'));

  test('保存后落在「自命名文件夹 / score.json」', () async {
    final saved = await repository.save(sample('长离-主C'));
    expect(saved.name, '长离-主C');
    expect(
      File(p.join(storage.scoresDir.path, '长离-主C', 'score.json')).existsSync(),
      isTrue,
    );
  });

  test('系数以快照形式写入，与来源配置解耦', () async {
    final saved = await repository.save(sample('快照'));
    final loaded = (await repository.loadAll()).items.single;
    expect(loaded.id, saved.id);
    expect(loaded.profileName, '长离');
    expect(loaded.coefficients[SubstatType.critRate], 1.0);
    expect(loaded.coefficients[SubstatType.atkPct], 0.75);
    expect(loaded.coefficients, hasLength(13));
  });

  test('5 个声骸槽位与档位、目标分完整往返', () async {
    final file = sample('往返').copyWith(
      echoes: [
        EchoEntry.create(0).withTier(SubstatType.critRate, 8),
        EchoEntry.create(1)
            .withTier(SubstatType.critDmg, 7)
            .withTier(SubstatType.atkPct, 6),
        EchoEntry(
          slot: 2,
          name: '主C声骸',
          tiers: const {SubstatType.energyRegen: 5},
        ).copyWith(targetScore: 66.6),
        EchoEntry.create(3),
        EchoEntry.create(4),
      ],
    );
    await repository.save(file);

    final loaded = (await repository.loadAll()).items.single;
    expect(loaded.echoes, hasLength(EchoEntry.slotCount));
    expect(loaded.echoes[0].tierOf(SubstatType.critRate), 8);
    expect(loaded.echoes[1].tierOf(SubstatType.critDmg), 7);
    expect(loaded.echoes[1].tierOf(SubstatType.atkPct), 6);
    expect(loaded.echoes[2].name, '主C声骸');
    expect(loaded.echoes[2].targetScore, 66.6);
    expect(loaded.echoes[3].tiers, isEmpty);
    expect(loaded.echoes[4].name, '声骸5');
  });

  test('声骸数据被截断时仍补齐 5 个槽位', () async {
    final file = sample('残缺');
    await repository.save(file);
    final entry = repository.entryOf(file);
    final json = jsonDecode(await entry.readAsString()) as Map<String, dynamic>;
    json['echoes'] = [
      {
        'slot': 3,
        'name': '声骸4',
        'tiers': {'critRate': 2},
      },
    ];
    await entry.writeAsString(jsonEncode(json));

    final loaded = (await repository.loadAll()).items.single;
    expect(loaded.echoes, hasLength(EchoEntry.slotCount));
    expect(loaded.echoes[3].tierOf(SubstatType.critRate), 2);
    expect(loaded.echoes[0].tiers, isEmpty);
  });

  test('重命名会移动文件夹并清掉旧目录', () async {
    final saved = await repository.save(sample('旧名'));
    final renamed = await repository.rename(saved, '新名');

    expect(renamed.name, '新名');
    expect(
      Directory(p.join(storage.scoresDir.path, '新名')).existsSync(),
      isTrue,
    );
    expect(
      Directory(p.join(storage.scoresDir.path, '旧名')).existsSync(),
      isFalse,
    );

    final loaded = (await repository.loadAll()).items;
    expect(loaded, hasLength(1));
    expect(loaded.single.name, '新名');
    expect(loaded.single.id, saved.id);
  });

  test('重命名为已存在的名字时自动追加序号', () async {
    await repository.save(sample('甲'));
    final second = await repository.save(sample('乙'));
    final renamed = await repository.rename(second, '甲');
    expect(renamed.name, '甲 (2)');
    expect((await repository.loadAll()).items, hasLength(2));
  });

  test('同名新建不会覆盖既有文件', () async {
    final first = await repository.save(sample('重名'));
    final second = await repository.save(sample('重名'));
    expect(second.name, '重名 (2)');
    expect(first.id, isNot(second.id));
    expect((await repository.loadAll()).items, hasLength(2));
  });

  test('删除会移除整个文件夹', () async {
    final saved = await repository.save(sample('待删除'));
    await repository.delete(saved);
    expect(
      Directory(p.join(storage.scoresDir.path, '待删除')).existsSync(),
      isFalse,
    );
    expect((await repository.loadAll()).items, isEmpty);
  });

  test('手工改动文件夹名后，显示名自愈', () async {
    final saved = await repository.save(sample('手工改名前'));
    await Directory(p.join(storage.scoresDir.path, '手工改名前'))
        .rename(p.join(storage.scoresDir.path, '手工改名后'));

    final loaded = (await repository.loadAll()).items.single;
    expect(loaded.id, saved.id);
    expect(loaded.name, '手工改名后');
  });

  test('损坏的评分文件被跳过并记录错误', () async {
    await repository.save(sample('正常'));
    final broken = Directory(p.join(storage.scoresDir.path, '坏文件'));
    await broken.create(recursive: true);
    await File(p.join(broken.path, 'score.json')).writeAsString('不是 JSON');

    final loaded = await repository.loadAll();
    expect(loaded.items, hasLength(1));
    expect(loaded.items.single.name, '正常');
    expect(loaded.hasErrors, isTrue);
    expect(loaded.errors.single, contains('坏文件'));
  });

  test('没有 score.json 的目录被忽略', () async {
    await Directory(p.join(storage.scoresDir.path, '空目录')).create();
    final loaded = await repository.loadAll();
    expect(loaded.items, isEmpty);
    expect(loaded.hasErrors, isFalse);
  });

  test('导入不会覆盖同 id 的既有文件', () async {
    final original = await repository.save(sample('原版'));
    await repository.save(
      original.withEcho(original.echoAt(0).withTier(SubstatType.critRate, 8)),
    );

    final payload = jsonDecode(
      jsonEncode((await repository.loadAll()).items.single.toJson()),
    ) as Map<String, dynamic>;
    payload['name'] = '原版';
    final imported = await repository.importScoreFile(
      ScoreFile.fromJson(payload),
    );

    expect(imported.id, isNot(original.id));
    expect(imported.name, '原版 (2)');
    final all = (await repository.loadAll()).items;
    expect(all, hasLength(2));
    expect(
      all
          .firstWhere((f) => f.id == original.id)
          .echoes[0]
          .tierOf(SubstatType.critRate),
      8,
    );
  });

  test('导入的文件名无法穿越出 scores 目录', () async {
    final file = sample('穿越');
    final payload =
        jsonDecode(jsonEncode(file.toJson())) as Map<String, dynamic>;
    payload['name'] = '../../../逃逸';
    final imported = await repository.importScoreFile(
      ScoreFile.fromJson(payload),
    );

    expect(
      p.dirname(repository.folderOf(imported).path),
      storage.scoresDir.path,
    );
    expect(Directory(p.join(tempRoot.path, '逃逸')).existsSync(), isFalse);
  });

  test('暴击阈值随文件落盘，缺键或非法值视为不设阈值', () async {
    final saved = await repository.save(
      sample('阈值').copyWith(critThreshold: 25.0),
    );
    final loaded = (await repository.loadAll()).items.single;
    expect(loaded.critThreshold, 25.0);
    expect(loaded.sameContentAs(saved), isTrue);

    final raw = File(p.join(repository.folderOf(saved).path, 'score.json'));
    final json = jsonDecode(await raw.readAsString()) as Map<String, dynamic>;
    expect(json['critThreshold'], 25.0);

    json.remove('critThreshold');
    await raw.writeAsString(jsonEncode(json));
    final reloaded = (await repository.loadAll()).items.single;
    expect(reloaded.critThreshold, isNull);
    expect(reloaded.sameContentAs(loaded), isFalse);

    json['critThreshold'] = -3;
    await raw.writeAsString(jsonEncode(json));
    expect((await repository.loadAll()).items.single.critThreshold, isNull);
  });

  test('写入不残留临时文件', () async {
    final saved = await repository.save(sample('原子性'));
    await repository.save(saved);
    final leftovers = repository
        .folderOf(saved)
        .listSync()
        .where((f) => f.path.contains('.tmp-'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test('切换存储根目录后，仓库指向新位置', () async {
    await repository.save(sample('旧根目录'));
    final otherRoot = await Directory.systemTemp.createTemp(
      'echo_scorer_other',
    );
    addTearDown(() async {
      if (await otherRoot.exists()) await otherRoot.delete(recursive: true);
    });
    await storage.changeRoot(otherRoot);

    expect((await repository.loadAll()).items, isEmpty);
    await repository.save(sample('新根目录'));
    expect(
      File(p.join(otherRoot.path, 'scores', '新根目录', 'score.json')).existsSync(),
      isTrue,
    );
  });
}
