import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/data/catalog/substat_type.dart';
import 'package:mingchao_echo_scorer/data/models/coefficient_profile.dart';
import 'package:mingchao_echo_scorer/data/repositories/profile_repository.dart';
import 'package:mingchao_echo_scorer/data/repositories/storage_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;
  late StorageService storage;
  late ProfileRepository repository;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('echo_scorer_profile');
    storage = StorageService(tempRoot);
    await storage.ensureStructure();
    repository = ProfileRepository(storage);
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  CoefficientProfile sample(String name) =>
      CoefficientProfile.create(name).copyWith(
        coefficients: {
          SubstatType.critRate: 1.0,
          SubstatType.critDmg: 0.9,
          SubstatType.atkPct: 0.75,
        },
      );

  /// 仓库只接收解析好的配置，JSON 解析交给模型层（见 [CoefficientProfile.fromJson]）。
  Future<CoefficientProfile> importJson(Map<String, dynamic> json) =>
      repository.importProfile(CoefficientProfile.fromJson(json));

  test('目录结构在初始化时建立', () async {
    expect(await storage.profilesDir.exists(), isTrue);
    expect(await storage.scoresDir.exists(), isTrue);
  });

  test('保存后能原样读回', () async {
    final saved = await repository.save(sample('长离'));
    expect(File(repository.fileOf(saved).path).existsSync(), isTrue);

    final loaded = await repository.loadAll();
    expect(loaded.errors, isEmpty);
    expect(loaded.items, hasLength(1));
    expect(loaded.items.single.id, saved.id);
    expect(loaded.items.single.name, '长离');
    expect(loaded.items.single.coefficients[SubstatType.critRate], 1.0);
    expect(loaded.items.single.coefficients[SubstatType.critDmg], 0.9);
    expect(loaded.items.single.coefficients[SubstatType.atkPct], 0.75);
    // 未设置的属性补 0，且 13 键齐全
    expect(loaded.items.single.coefficients, hasLength(13));
    expect(loaded.items.single.coefficients[SubstatType.flatDef], 0.0);
  });

  test('按 id 查找', () async {
    final saved = await repository.save(sample('守岸人'));
    final found = await repository.findById(saved.id);
    expect(found?.name, '守岸人');
    expect(await repository.findById('不存在的id'), isNull);
    expect(await repository.findById(''), isNull);
  });

  test('重命名走 save，不产生重复文件', () async {
    final saved = await repository.save(sample('旧名字'));
    await repository.save(saved.copyWith(name: '新名字'));

    final loaded = await repository.loadAll();
    expect(loaded.items, hasLength(1));
    expect(loaded.items.single.name, '新名字');
    final files = storage.profilesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(files, hasLength(1));
  });

  test('同名配置自动追加序号', () async {
    await repository.save(sample('长离'));
    final second = await repository.save(sample('长离'));
    expect(second.name, '长离 (2)');
    final loaded = await repository.loadAll();
    expect(loaded.items, hasLength(2));
  });

  test('非法名称被规范化', () async {
    final saved = await repository.save(sample('长离/主C:毕业'));
    expect(saved.name, '长离_主C_毕业');
  });

  test('删除后不再出现', () async {
    final saved = await repository.save(sample('待删除'));
    await repository.delete(saved.id);
    final loaded = await repository.loadAll();
    expect(loaded.items, isEmpty);
  });

  test('损坏的文件被跳过并记录错误，不影响其余配置', () async {
    await repository.save(sample('正常'));
    await File(p.join(storage.profilesDir.path, '坏文件.json'))
        .writeAsString('{ 这不是 JSON');

    final loaded = await repository.loadAll();
    expect(loaded.items, hasLength(1));
    expect(loaded.items.single.name, '正常');
    expect(loaded.hasErrors, isTrue);
    expect(loaded.errors.single, contains('坏文件.json'));
  });

  test('导入时未知键忽略、缺失键补 0', () async {
    final imported = await importJson({
      'format': 1,
      'id': 'imported-id',
      'name': '外部配置',
      'coefficients': {'critRate': 1.0, '不存在的属性': 5.0, 'flatDef': -3.0},
    });
    expect(imported.name, '外部配置');
    expect(imported.coefficients, hasLength(13));
    expect(imported.coefficients[SubstatType.critRate], 1.0);
    expect(imported.coefficients[SubstatType.flatDef], 0.0, reason: '负值夹到 0');
  });

  test('导入重名配置时追加序号', () async {
    await repository.save(sample('长离'));
    final imported = await importJson(sample('长离').toJson());
    expect(imported.name, '长离 (2)');
    expect(await repository.loadAll().then((r) => r.items), hasLength(2));
  });

  test('导入不会覆盖同 id 的既有配置', () async {
    final original = await repository.save(sample('原版'));
    final payload =
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
    payload['name'] = '篡改版';
    payload['coefficients'] = {'critRate': 9.0};

    final imported = await importJson(payload);
    expect(imported.id, isNot(original.id));

    final stillThere = await repository.findById(original.id);
    expect(stillThere?.name, '原版');
    expect(stillThere?.coefficients[SubstatType.critRate], 1.0);
  });

  test('导入的 id 无法穿越出 profiles 目录', () async {
    final imported = await importJson({
      'format': 1,
      'id': '../../../../evil',
      'name': '恶意配置',
      'coefficients': {'critRate': 1.0},
    });
    expect(
      p.dirname(repository.fileOf(imported).path),
      storage.profilesDir.path,
    );
    expect(File(p.join(tempRoot.path, 'evil.json')).existsSync(), isFalse);
  });

  test('JSON 往返保持系数与元数据', () async {
    final profile = sample('往返测试');
    final decoded = CoefficientProfile.fromJson(
      jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.id, profile.id);
    expect(decoded.name, profile.name);
    expect(decoded.coefficients, profile.coefficients);
    expect(
      decoded.createdAt.millisecondsSinceEpoch,
      profile.createdAt.millisecondsSinceEpoch,
    );
  });

  test('写入是原子替换，不留临时文件', () async {
    final saved = await repository.save(sample('原子性'));
    await repository.save(saved.copyWith(name: '原子性2'));
    final leftovers = storage.profilesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.tmp-'))
        .toList();
    expect(leftovers, isEmpty);
  });
}
