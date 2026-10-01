import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/ui/widgets/app_background.dart';

void main() {
  testWidgets('imagePath 为空串时原样返回 child，不渲染图片或遮罩', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppBackground(
          imagePath: '',
          child: Center(child: Text('内容')),
        ),
      ),
    );

    expect(find.text('内容'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('imagePath 为 null 时同样不渲染背景', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppBackground(imagePath: null, child: Center(child: Text('内容'))),
      ),
    );

    expect(find.text('内容'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
