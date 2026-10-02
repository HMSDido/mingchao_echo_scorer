import 'dart:convert';

import 'coefficient_profile.dart';
import 'score_file.dart';

/// 剪贴板分享的通用编解码：`echoscorer://` + Base64(UTF-8 JSON)，多条按行拼接。
///
/// Base64 让中文和引号不会在粘贴、聊天软件转义时损坏，也避免把内容直接摊在
/// 链接里。纯 Dart、不依赖 Flutter，方便单元测试。
///
/// 约定：trim 后以 `#` 开头的行是给人看的说明行（如 `# 31绯雪系数配置`），
/// 解析时与空行一样直接跳过，不计入失败。
class ShareLink {
  const ShareLink._();

  static const String scheme = 'echoscorer://';

  /// 注释行前缀：只给人看，程序整行跳过。
  static const String commentPrefix = '#';

  static String encode(Map<String, dynamic> json, {String? comment}) {
    final link = '$scheme${base64Encode(utf8.encode(jsonEncode(json)))}';
    final note = comment?.trim();
    return note == null || note.isEmpty ? link : '$commentPrefix $note\n$link';
  }

  /// 解析剪贴板文本。
  ///
  /// `#` 说明行与空行一律跳过（不算失败）；先整体试一次 JSON——社区仓库里
  /// 分享的配置是多行美化 JSON，整段粘贴进来也要能读；再按行拆分逐条解析，
  /// 坏行只记进 [ShareLinkResult.failures]，不影响同批的其他条目。
  static ShareLinkResult<T> parse<T>(String raw, ShareDecoder<T> decode) {
    final text = raw.trim();
    if (text.isEmpty) {
      return ShareLinkResult(items: const [], failures: const []);
    }

    final lines = text.split(RegExp(r'\r?\n'));
    final body = lines
        .where((line) => !line.trim().startsWith(commentPrefix))
        .join('\n')
        .trim();
    if (body.isEmpty) {
      return ShareLinkResult(items: const [], failures: const []);
    }

    final whole = _decodeOrNull(body, decode);
    if (whole != null) {
      return ShareLinkResult(items: [whole], failures: const []);
    }

    final items = <T>[];
    final failures = <String>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.isEmpty || line.startsWith(commentPrefix)) continue;
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

  /// 单条编码自带人读说明头，如 `# 31绯雪系数配置`。
  static String encode(CoefficientProfile profile) =>
      ShareLink.encode(profile.toJson(), comment: '${profile.name}系数配置');

  static String encodeAll(Iterable<CoefficientProfile> profiles) =>
      profiles.map(encode).join('\n');

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

  /// 单条编码自带人读说明头，如 `# 长离毕业套评分文件`。
  static String encode(ScoreFile file) =>
      ShareLink.encode(file.toJson(), comment: '${file.name}评分文件');

  static String encodeAll(Iterable<ScoreFile> files) =>
      files.map(encode).join('\n');

  static ShareLinkResult<ScoreFile> parse(String raw) =>
      ShareLink.parse(raw, _decode);

  static ScoreFile _decode(Map<String, dynamic> json) {
    if (json['echoes'] is! List) {
      throw const FormatException('这是角色系数配置，请到「编辑角色系数」页导入');
    }
    return ScoreFile.fromJson(json);
  }
}
