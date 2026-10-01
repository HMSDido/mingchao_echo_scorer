import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/core/util/file_names.dart';
import 'package:path/path.dart' as p;

void main() {
  group('sanitize', () {
    test('替换 Windows 非法字符', () {
      expect(FileNames.sanitize(r'长离/主C:dos', fallback: 'x'), '长离_主C_dos');
      expect(
        FileNames.sanitize('a*b?c"d<e>f|g', fallback: 'x'),
        'a_b_c_d_e_f_g',
      );
    });

    test('去掉首尾空格与结尾的点', () {
      expect(FileNames.sanitize('  长离  ', fallback: 'x'), '长离');
      expect(FileNames.sanitize('长离...', fallback: 'x'), '长离');
    });

    test('空名或保留名回退到 fallback', () {
      expect(FileNames.sanitize('', fallback: '未命名文件'), '未命名文件');
      expect(FileNames.sanitize('   ', fallback: '未命名文件'), '未命名文件');
      expect(FileNames.sanitize('CON', fallback: '未命名文件'), '未命名文件');
      expect(FileNames.sanitize('nul', fallback: '未命名文件'), '未命名文件');
      expect(FileNames.sanitize('COM1', fallback: '未命名文件'), '未命名文件');
    });

    test('阻止路径穿越', () {
      for (final malicious in [
        '../../etc/passwd',
        r'..\..\Windows\System32',
        '/absolute/path',
        r'C:\Windows',
      ]) {
        final result = FileNames.sanitize(malicious, fallback: '未命名文件');
        expect(result, isNot(contains('/')), reason: malicious);
        expect(result, isNot(contains(r'\')), reason: malicious);
        // 清理后的名字拼进根目录，规范化后仍必须落在根目录之内。
        final root = r'E:\data\scores';
        final resolved = p.normalize(p.join(root, result));
        expect(p.isWithin(root, resolved), isTrue, reason: malicious);
      }
    });

    test('超长名被截断', () {
      final long = 'a' * 200;
      expect(
        FileNames.sanitize(long, fallback: 'x').length,
        lessThanOrEqualTo(60),
      );
    });

    test('中文名与常规字符原样保留', () {
      expect(FileNames.sanitize('长离-主C (毕业)', fallback: 'x'), '长离-主C (毕业)');
      expect(FileNames.isSafe('长离-主C'), isTrue);
      expect(FileNames.isSafe('a/b'), isFalse);
      expect(FileNames.isSafe(''), isFalse);
    });
  });

  group('deduplicate', () {
    test('无冲突时原样返回', () {
      expect(FileNames.deduplicate('长离', ['相里要']), '长离');
      expect(FileNames.deduplicate('长离', []), '长离');
    });

    test('冲突时追加序号，并跳过已占用的序号', () {
      expect(FileNames.deduplicate('长离', ['长离']), '长离 (2)');
      expect(FileNames.deduplicate('长离', ['长离', '长离 (2)']), '长离 (3)');
      expect(FileNames.deduplicate('长离', ['长离', '长离 (2)', '长离 (3)']), '长离 (4)');
    });
  });
}
