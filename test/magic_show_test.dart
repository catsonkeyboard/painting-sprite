import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:painting_sprite/magic/magic_show.dart';

/// 回归：魔法屏初始愿望是 dance，MagicShow 只在 wish 变化时 repeat 的话，
/// 点"跳舞"按钮（wish 不变、autoPlay false→true）涂鸦全程静止。
void main() {
  Widget wrap(bool autoPlay) => MaterialApp(
        home: Center(
          child: MagicShow(
            wish: WishType.dance,
            autoPlay: autoPlay,
            child: const SizedBox(width: 50, height: 50),
          ),
        ),
      );

  testWidgets('autoPlay false→true 启动动画（默认愿望 dance 也要动）', (tester) async {
    await tester.pumpWidget(wrap(false));
    expect(SchedulerBinding.instance.transientCallbackCount, 0,
        reason: 'idle 时不应有动画在跑');

    await tester.pumpWidget(wrap(true));
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0),
        reason: 'autoPlay 变 true 后动画必须推进');
  });

  testWidgets('autoPlay true→false 停止动画', (tester) async {
    await tester.pumpWidget(wrap(true));
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(wrap(false));
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('播放中切换愿望：动画保持推进', (tester) async {
    await tester.pumpWidget(wrap(true));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: MagicShow(
          wish: WishType.fly,
          autoPlay: true,
          child: const SizedBox(width: 50, height: 50),
        ),
      ),
    ));
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));
  });
}
