import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:painting_sprite/main.dart';

void main() {
  testWidgets('首页三入口渲染 + 导航到画画屏', (WidgetTester tester) async {
    await tester.pumpWidget(const PaintingSpriteApp());

    // 首页标题与三个大入口
    expect(find.text('🖌️ 涂鸦精灵'), findsOneWidget);
    expect(find.text('🖌️'), findsOneWidget);
    expect(find.text('🎨'), findsOneWidget);
    expect(find.text('✨'), findsOneWidget);

    // 进入画画屏
    await tester.tap(find.text('🖌️'));
    await tester.pumpAndSettle();

    // 画画屏有完成按钮（auto_awesome 图标）
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsOneWidget);
  });

  testWidgets('画画屏：画一笔 → 完成 → 进入魔法屏', (WidgetTester tester) async {
    await tester.pumpWidget(const PaintingSpriteApp());
    await tester.tap(find.text('🖌️'));
    await tester.pumpAndSettle();

    // 在画布中央拖一笔
    final center = tester.getCenter(find.byType(ClipRRect).first);
    await tester.dragFrom(center, const Offset(60, 40));
    await tester.pumpAndSettle();

    // 点完成（魔法棒按钮）→ PNG 编码是真实异步，需 runAsync 放行真实时间
    await tester.tap(find.byIcon(Icons.auto_awesome));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 魔法屏出现 4 个愿望按钮
    expect(find.text('🕺'), findsOneWidget);
    expect(find.text('🕊️'), findsOneWidget);
    expect(find.text('🎤'), findsOneWidget);
    expect(find.text('🏃'), findsOneWidget);
  });
}
