import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/state/library_layout.dart';

/// 用 `p:` 前缀构造布局，断言时直接比较 token 序列。
LibraryLayout build(List<String> tokens) =>
    LibraryLayout(idPrefix: 'p:', tokens: tokens);

void main() {
  group('解析与序列化', () {
    test('token 往返一致', () {
      final layout = build(['g:绯雪', 'p:a', 'p:b', 'g:忌炎', 'p:c']);
      expect(layout.tokens, ['g:绯雪', 'p:a', 'p:b', 'g:忌炎', 'p:c']);
      expect(layout.rowCount, 5);
      expect(layout.rowIsGroup(0), isTrue);
      expect(layout.rowValue(0), '绯雪');
      expect(layout.rowIsGroup(1), isFalse);
    });

    test('无法识别的 token 与重复项被丢弃', () {
      final layout = build(['乱码', 'p:a', 'p:a', 'g:组', 'g:组', 's:b']);
      expect(layout.tokens, ['p:a', 'g:组']);
    });

    test('空组名的标题被丢弃', () {
      expect(build(['g:', 'p:a']).tokens, ['p:a']);
    });
  });

  group('对账 mergeWith', () {
    test('丢弃不存在的条目，新条目按给定顺序补到根层末尾', () {
      final layout = build(['p:a', 'g:组', 'p:b']);
      layout.mergeWith(['a', 'b', 'x', 'y']);
      expect(layout.tokens, ['p:a', 'p:x', 'p:y', 'g:组', 'p:b']);
    });

    test('布局外的组标题即使空了也保留', () {
      final layout = build(['g:空组']);
      layout.mergeWith(['a']);
      expect(layout.tokens, ['p:a', 'g:空组']);
    });

    test('条目消失后从布局移除', () {
      final layout = build(['g:组', 'p:a', 'p:b']);
      layout.mergeWith(['b']);
      expect(layout.tokens, ['g:组', 'p:b']);
    });
  });

  group('组操作', () {
    test('addGroup 追加到末尾，拒绝重名与空白名', () {
      final layout = build(['p:a']);
      expect(layout.addGroup('新组'), isTrue);
      expect(layout.tokens, ['p:a', 'g:新组']);
      expect(layout.addGroup('新组'), isFalse);
      expect(layout.addGroup('  '), isFalse);
    });

    test('renameGroup 更新标题，拒绝撞名', () {
      final layout = build(['g:甲', 'p:a', 'g:乙']);
      expect(layout.renameGroup('甲', '丙'), isTrue);
      expect(layout.groupNames, ['丙', '乙']);
      expect(layout.renameGroup('丙', '乙'), isFalse);
      expect(layout.renameGroup('不存在', '丁'), isFalse);
    });

    test('deleteGroup 把成员释放到根层末尾（第一个组标题之前）', () {
      final layout = build(['p:root', 'g:甲', 'p:a', 'p:b', 'g:乙', 'p:c']);
      layout.deleteGroup('甲');
      expect(layout.tokens, ['p:root', 'p:a', 'p:b', 'g:乙', 'p:c']);
    });

    test('deleteGroup 只剩标题本身时等价于移除标题', () {
      final layout = build(['g:甲', 'g:乙', 'p:a']);
      layout.deleteGroup('甲');
      expect(layout.tokens, ['g:乙', 'p:a']);
    });

    test('insertIntoGroup 插在组头，已在别处则移动', () {
      final layout = build(['p:a', 'g:甲', 'p:b']);
      expect(layout.insertIntoGroup('甲', 'a'), isTrue);
      expect(layout.tokens, ['g:甲', 'p:a', 'p:b']);
      expect(layout.insertIntoGroup('不存在', 'a'), isFalse);
    });

    test('appendToRoot 把组内条目移回根层', () {
      final layout = build(['g:甲', 'p:a']);
      layout.appendToRoot('a');
      expect(layout.tokens, ['p:a', 'g:甲']);
    });

    test('groupMemberIds 与 rootItemIds', () {
      final layout = build(['p:r', 'g:甲', 'p:a', 'g:乙']);
      expect(layout.groupMemberIds('甲'), ['a']);
      expect(layout.groupMemberIds('乙'), isEmpty);
      expect(layout.groupMemberIds('不存在'), isEmpty);
      expect(layout.rootItemIds, ['r']);
    });
  });

  group('拖拽重排 moveNode', () {
    test('条目移动到后面的位置（ReorderableListView 原始下标语义）', () {
      final layout = build(['p:a', 'p:b', 'p:c']);
      layout.moveNode(0, 2);
      expect(layout.tokens, ['p:b', 'p:a', 'p:c']);
    });

    test('条目移动到前面', () {
      final layout = build(['p:a', 'p:b', 'p:c']);
      layout.moveNode(2, 0);
      expect(layout.tokens, ['p:c', 'p:a', 'p:b']);
    });

    test('条目可以拖进组和拖出组', () {
      final layout = build(['p:a', 'g:甲', 'p:b']);
      layout.moveNode(0, 3); // 拖过末尾：进入组内并落到最后
      expect(layout.tokens, ['g:甲', 'p:b', 'p:a']);
      layout.moveNode(2, 0); // 拖到最前：回到根层
      expect(layout.tokens, ['p:a', 'g:甲', 'p:b']);
    });

    test('拖动组标题时整组移动', () {
      final layout = build(['g:甲', 'p:a', 'p:b', 'g:乙', 'p:c']);
      // 把「甲」组拖到「乙」之前：甲本来就在前面，落点在自身范围内 → 无操作
      layout.moveNode(0, 3);
      expect(layout.tokens, ['g:甲', 'p:a', 'p:b', 'g:乙', 'p:c']);
      // 把「乙」组拖到「甲」标题上：整组提到最前
      layout.moveNode(3, 0);
      expect(layout.tokens, ['g:乙', 'p:c', 'g:甲', 'p:a', 'p:b']);
    });

    test('整组向后移动时成员跟随', () {
      final layout = build(['g:甲', 'p:a', 'g:乙', 'p:b', 'g:丙']);
      layout.moveNode(0, 4);
      expect(layout.tokens, ['g:乙', 'p:b', 'g:甲', 'p:a', 'g:丙']);
    });

    test('落点在自身组内部不生效', () {
      final layout = build(['g:甲', 'p:a', 'p:b']);
      layout.moveNode(0, 2);
      expect(layout.tokens, ['g:甲', 'p:a', 'p:b']);
    });

    test('空组也可以整体拖动', () {
      final layout = build(['g:甲', 'g:乙']);
      layout.moveNode(1, 0);
      expect(layout.tokens, ['g:乙', 'g:甲']);
    });
  });
}
