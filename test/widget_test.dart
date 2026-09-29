import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:painting_sprite/main.dart';

void main() {
  testWidgets('首页四入口渲染 + 导航到画画屏', (WidgetTester tester) async {
    await tester.pumpWidget(const PaintingSpriteApp());

    // 首页标题与四个大入口：画画/涂色/相册/设置
    expect(find.text('🖌️ 涂鸦精灵'), findsOneWidget);
    expect(find.text('🖌️'), findsOneWidget);
    expect(find.text('🎨'), findsOneWidget);
    expect(find.text('🖼️'), findsOneWidget);
    expect(find.text('⚙️'), findsOneWidget);

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

    // 点完成（魔法棒按钮）→ PNG 编码 + TTS 播报是真实异步，runAsync 放行真实时间
    await tester.tap(find.byIcon(Icons.auto_awesome));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // 再放行一轮（speak 完成后 onDone 才触发导航）
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 魔法屏出现愿望按钮（4 个愿望 emoji）
    expect(find.text('🕺'), findsOneWidget);
    expect(find.text('🕊️'), findsOneWidget);
    expect(find.text('🏃'), findsOneWidget);
    // 麦克风按钮存在（至少 1 个）
    expect(find.text('🎤'), findsWidgets);
  });

  testWidgets('涂色屏：线稿库网格渲染 + 点选进入涂色', (WidgetTester tester) async {
    await tester.pumpWidget(const PaintingSpriteApp());
    await tester.tap(find.text('🎨'));
    await tester.pumpAndSettle();

    // 麦克风 + 8 张内置线稿缩略图（Image.asset）
    expect(find.text('🎤'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);

    // 点第一张线稿 → 进入涂色模式（图像解码是真实异步，放行真实时间）
    await tester.tap(find.byType(Image).first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });
}
