import 'dart:convert';

import 'coefficient_profile.dart';
import 'score_file.dart';

/// 剪贴板分享的通用编解码：`echoscorer://` + Base64(UTF-8 JSON)，多条按行拼接。
///
/// Base64 让中文和引号不会在粘贴、聊天软件转义时损坏，也避免把内容直接摊在
/// 链接里。纯 Dart、不依赖 Flutter，方便单元测试。
class ShareLink {
  const ShareLink._();

  static const String scheme = 'echoscorer://';

  static String encode(Map<String, dynamic> json) =>
      '$scheme${base64Encode(utf8.encode(jsonEncode(json)))}';

  static String encodeAll(Iterable<Map<String, dynamic>> items) =>
      items.map(encode).join('\n');

  /// 解析剪贴板文本。
  ///
  /// 先整体试一次 JSON——社区仓库里分享的配置是多行美化 JSON，整段粘贴进来
  /// 也要能读；再按行拆分逐条解析，坏行只记进 [ShareLinkResult.failures]，
  /// 不影响同批的其他条目。空行直接跳过，不算失败。
  static ShareLinkResult<T> parse<T>(String raw, ShareDecoder<T> decode) {
    final text = raw.trim();
    if (text.isEmpty) {
      return ShareLinkResult(items: const [], failures: const []);
    }

    final whole = _decodeOrNull(text, decode);
    if (whole != null) {
      return ShareLinkResult(items: [whole], failures: const []);
    }

    final items = <T>[];
    final failures = <String>[];
    final lines = text.split(RegExp(r'\r?\n'));
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.isEmpty) continue;
      try {
        items.add(_decode(line, decode));
      } on FormatException catch (error) {
        final reason = error.message.isEmpty ? '无法识别的内容' : error.message;
        failures.add('第 ${index + 1} 行：$reason');
      }
    }
    return ShareLinkResult(items: items, failures: failures);
  }

  static T? _decodeOrNull<T>(String text, ShareDecoder<T> decode) {
    try {
      return _decode(text, decode);
    } on FormatException {
      return null;
    }
  }

  /// 解析一行：分享链接优先，其次是裸 JSON。
  static T _decode<T>(String text, ShareDecoder<T> decode) {
    if (text.length > scheme.length &&
        text.substring(0, scheme.length).toLowerCase() == scheme) {
      return decode(_jsonOfBase64(text.substring(scheme.length)));
    }
    if (!text.startsWith('{')) {
      throw const FormatException('无法识别的内容');
    }
    return decode(_jsonOf(jsonDecode(text)));
  }

  static Map<String, dynamic> _jsonOfBase64(String payload) {
    // 容忍 URL-safe 变体、粘贴时混入的空白，以及被裁掉的 `=` 填充。
    final body = payload
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    if (body.isEmpty || body.length % 4 == 1) {
      throw const FormatException('分享链接不完整');
    }
    final padded = body.padRight(body.length + (4 - body.length % 4) % 4, '=');
    return _jsonOf(jsonDecode(utf8.decode(base64Decode(padded))));
  }

  static Map<String, dynamic> _jsonOf(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('不是一段合法的数据');
    }
    return decoded;
  }
}

/// 把一段 JSON 还原成模型；结构不对时抛 [FormatException]，原因会展示给用户。
typedef ShareDecoder<T> = T Function(Map<String, dynamic> json);

/// [ShareLink.parse] 的结果：成功的条目 + 每行失败的原因。
class ShareLinkResult<T> {
  const ShareLinkResult({required this.items, required this.failures});

  final List<T> items;
  final List<String> failures;
}

/// 一次剪贴板导入的结果：成功条数 + 每条失败原因。
typedef ShareImportSummary = ({int imported, List<String> failures});

/// 角色系数配置的分享链接。
class ProfileShare {
  const ProfileShare._();

  static String encode(CoefficientProfile profile) =>
      ShareLink.encode(profile.toJson());

  static String encodeAll(Iterable<CoefficientProfile> profiles) =>
      ShareLink.encodeAll(profiles.map((profile) => profile.toJson()));

  static ShareLinkResult<CoefficientProfile> parse(String raw) =>
      ShareLink.parse(raw, _decode);

  static CoefficientProfile _decode(Map<String, dynamic> json) {
    if (json['echoes'] is List) {
      throw const FormatException('这是评分文件，请到评分文件列表用「粘贴导入」');
    }
    return CoefficientProfile.fromJson(json);
  }
}

/// 评分文件的分享链接。
class ScoreShare {
  const ScoreShare._();

  static String encode(ScoreFile file) => ShareLink.encode(file.toJson());

  static String encodeAll(Iterable<ScoreFile> files) =>
      ShareLink.encodeAll(files.map((file) => file.toJson()));

  static ShareLinkResult<ScoreFile> parse(String raw) =>
      ShareLink.parse(raw, _decode);

  static ScoreFile _decode(Map<String, dynamic> json) {
    if (json['echoes'] is! List) {
      throw const FormatException('这是角色系数配置，请到「编辑角色系数」页导入');
    }
    return ScoreFile.fromJson(json);
  }
}
