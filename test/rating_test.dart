import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/data/models/rating.dart';

void main() {
  group('评级阈值', () {
    test('恰好命中阈值时取较高一档', () {
      expect(Rating.fromRatio(0.80), Rating.ace);
      expect(Rating.fromRatio(0.70), Rating.s);
      expect(Rating.fromRatio(0.60), Rating.a);
      expect(Rating.fromRatio(0.50), Rating.b);
      expect(Rating.fromRatio(0.40), Rating.c);
    });

    test('浮点表示误差不会导致降级', () {
      // 0.8、0.7、0.6 等在二进制下都无法精确表示，比值计算会带微小误差。
      expect(Rating.fromRatio(32 / 40), Rating.ace); // 恰为 80%
      expect(Rating.fromScore(32, 40), Rating.ace);
      expect(Rating.fromScore(21, 30), Rating.s); // 恰为 70%
      expect(Rating.fromScore(24, 40), Rating.a); // 恰为 60%
      expect(Rating.fromRatio(0.8 - 1e-12), Rating.ace);
      expect(Rating.fromRatio(0.7 - 1e-12), Rating.s);
    });

    test('略低于阈值时降一级', () {
      expect(Rating.fromRatio(0.7999), Rating.s);
      expect(Rating.fromRatio(0.6999), Rating.a);
      expect(Rating.fromRatio(0.5999), Rating.b);
      expect(Rating.fromRatio(0.4999), Rating.c);
      expect(Rating.fromRatio(0.3999), Rating.none);
    });

    test('低于 40% 无评级', () {
      expect(Rating.fromRatio(0.39), Rating.none);
      expect(Rating.fromRatio(0.0), Rating.none);
      expect(Rating.fromRatio(-1), Rating.none);
      expect(Rating.fromRatio(double.nan), Rating.none);
      expect(Rating.none.isRated, isFalse);
      expect(Rating.c.isRated, isTrue);
    });

    test('理论最高分为 0 时无评级', () {
      expect(Rating.fromScore(0, 0), Rating.none);
      expect(Rating.fromScore(10, 0), Rating.none);
    });

    test('超过 100% 仍为 ACE', () {
      expect(Rating.fromRatio(1.0), Rating.ace);
      expect(Rating.fromRatio(1.5), Rating.ace);
    });

    test('显示文本', () {
      expect(Rating.ace.label, 'ACE');
      expect(Rating.s.label, 'S');
      expect(Rating.none.label, '—');
    });
  });
}
