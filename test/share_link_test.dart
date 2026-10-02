import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/data/catalog/substat_type.dart';
import 'package:mingchao_echo_scorer/data/models/coefficient_profile.dart';
import 'package:mingchao_echo_scorer/data/models/coefficients.dart';
import 'package:mingchao_echo_scorer/data/models/echo_entry.dart';
import 'package:mingchao_echo_scorer/data/models/score_file.dart';
import 'package:mingchao_echo_scorer/data/models/share_link.dart';

void main() {
  final timestamp = DateTime.utc(2026, 10, 2, 8, 30);

  CoefficientProfile sampleProfile(String id, String name) =>
      CoefficientProfile(
        id: id,
        name: name,
        coefficients: normalizeCoefficients({
          SubstatType.critRate: 1.0,
          SubstatType.critDmg: 0.9,
          SubstatType.atkPct: 0.75,
        }),
        createdAt: timestamp,
        updatedAt: timestamp,
      );

  ScoreFile sampleScore(String id, String name) =>
      ScoreFile(
        id: id,
        name: name,
        profileId: 'abc123',
        profileName: '长离',
        coefficients: normalizeCoefficients({SubstatType.critRate: 1.0}),
        echoes: List.generate(EchoEntry.slotCount, EchoEntry.create),
        updatedAt: timestamp,
        critThreshold: 25.0,
      ).withEcho(
        EchoEntry.create(0)
            .copyWith(name: '哀声鸷·主词条', targetScore: 88.5)
            .withTier(SubstatType.critRate, 4),
      );

  group('编码', () {
    test('分享链接是 echoscorer:// + Base64，不暴露配置明文', () {
      final link = ProfileShare.encode(sampleProfile('abc123', '长离'));

      expect(link, startsWith(ShareLink.scheme));
      expect(link, isNot(contains('长离')));
      expect(link, isNot(contains('{')));
    });

    test('多条配置按行拼接，每行都是完整链接', () {
      final text = ProfileShare.encodeAll([
        sampleProfile('a1', '长离'),
        sampleProfile('b2', '守岸人'),
        sampleProfile('c3', '卡卡罗'),
      ]);

      final lines = text.split('\n');
      expect(lines, hasLength(3));
      expect(lines.every((line) => line.startsWith(ShareLink.scheme)), isTrue);
    });

    test('评分文件同样走分享链接编码', () {
      final link = ScoreShare.encode(sampleScore('f1', '长离毕业套'));

      expect(link, startsWith(ShareLink.scheme));
      expect(link, isNot(contains('长离毕业套')));
      expect(link, isNot(contains('哀声鸷')));
    });
  });

  group('配置解析', () {
    test('往返保留 id、中文名、系数与时间', () {
      final origin = sampleProfile('abc123', '长离·主C');

      final result = ProfileShare.parse(ProfileShare.encode(origin));

      expect(result.failures, isEmpty);
      final decoded = result.items.single;
      expect(decoded.id, origin.id);
      expect(decoded.name, origin.name);
      expect(decoded.coefficients, origin.coefficients);
      expect(decoded.updatedAt, origin.updatedAt);
    });

    test('批量粘贴按原顺序还原', () {
      final text = ProfileShare.encodeAll([
        sampleProfile('a1', '长离'),
        sampleProfile('b2', '守岸人'),
        sampleProfile('c3', '卡卡罗'),
      ]);

      final result = ProfileShare.parse(text);

      expect(result.failures, isEmpty);
      expect(result.items.map((profile) => profile.id), ['a1', 'b2', 'c3']);
    });

    test('空行被跳过，不计入失败', () {
      final link = ProfileShare.encode(sampleProfile('a1', '长离'));

      final result = ProfileShare.parse('\n$link\n\n$link\n');

      expect(result.items, hasLength(2));
      expect(result.failures, isEmpty);
    });

    test('坏行只记行号，不影响同批其他配置', () {
      final link = ProfileShare.encode(sampleProfile('a1', '长离'));

      final result = ProfileShare.parse(
        '$link\n随便一段文字\n${ShareLink.scheme}!!!!\n$link',
      );

      expect(result.items.map((profile) => profile.id), ['a1', 'a1']);
      expect(result.failures, hasLength(2));
      expect(result.failures[0], startsWith('第 2 行'));
      expect(result.failures[1], startsWith('第 3 行'));
    });

    test('前缀大小写不敏感，CRLF 换行也能拆', () {
      final link = ProfileShare.encode(sampleProfile('a1', '长离'));
      final upper = 'ECHOSCORER://${link.substring(ShareLink.scheme.length)}';

      final result = ProfileShare.parse('$upper\r\n$link');

      expect(result.failures, isEmpty);
      expect(result.items.map((profile) => profile.id), ['a1', 'a1']);
    });

    test('裸 JSON 单行可以直接粘贴', () {
      final result = ProfileShare.parse(
        jsonEncode(sampleProfile('a1', '长离').toJson()),
      );

      expect(result.failures, isEmpty);
      expect(result.items.single.name, '长离');
    });

    test('社区仓库那种多行美化 JSON 整段粘贴也能读', () {
      final pretty = const JsonEncoder.withIndent('  ')
          .convert(sampleProfile('a1', '长离').toJson());

      final result = ProfileShare.parse(pretty);

      expect(result.failures, isEmpty);
      expect(result.items.single.id, 'a1');
    });

    test('URL-safe 字母表与被裁掉的 = 填充都能解', () {
      final payload = base64Url
          .encode(utf8.encode(jsonEncode(sampleProfile('a1', '长离').toJson())))
          .replaceAll('=', '');

      final result = ProfileShare.parse('${ShareLink.scheme}$payload');

      expect(result.failures, isEmpty);
      expect(result.items.single.id, 'a1');
    });

    test('缺 id 的配置被拒并说明原因', () {
      final result = ProfileShare.parse(
        jsonEncode(sampleProfile('a1', '长离').toJson()..remove('id')),
      );

      expect(result.items, isEmpty);
      expect(result.failures.single, contains('id'));
    });

    test('空剪贴板返回空结果', () {
      expect(ProfileShare.parse('   \n ').items, isEmpty);
      expect(ProfileShare.parse('').failures, isEmpty);
    });
  });

  group('评分文件解析', () {
    test('往返保留声骸录入、系数快照与暴击阈值', () {
      final origin = sampleScore('f1', '长离毕业套');

      final result = ScoreShare.parse(ScoreShare.encode(origin));

      expect(result.failures, isEmpty);
      final decoded = result.items.single;
      expect(decoded.id, origin.id);
      expect(decoded.name, origin.name);
      expect(decoded.profileName, origin.profileName);
      expect(decoded.critThreshold, origin.critThreshold);
      expect(decoded.sameContentAs(origin), isTrue);
    });

    test('缺 id 的评分文件被拒', () {
      final result = ScoreShare.parse(
        jsonEncode(sampleScore('f1', '长离毕业套').toJson()..remove('id')),
      );

      expect(result.items, isEmpty);
      expect(result.failures.single, contains('id'));
    });
  });

  group('两种数据粘错地方', () {
    test('把评分文件链接粘进配置导入，提示去评分文件列表', () {
      final result = ProfileShare.parse(
        ScoreShare.encode(sampleScore('f1', '长离毕业套')),
      );

      expect(result.items, isEmpty);
      expect(result.failures.single, contains('评分文件'));
    });

    test('把配置链接粘进评分文件导入，提示去编辑角色系数页', () {
      final result = ScoreShare.parse(
        ProfileShare.encode(sampleProfile('a1', '长离')),
      );

      expect(result.items, isEmpty);
      expect(result.failures.single, contains('角色系数配置'));
    });
  });
}
