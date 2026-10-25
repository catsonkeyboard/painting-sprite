import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:painting_sprite/main.dart';
import 'package:painting_sprite/services/ai_keys.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);
  final Directory dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

/// 模型配置页（家长门后）：状态徽章实时反映表单，保存落盘应用内配置。
///
/// fake async 注意事项：
/// 1. 任何真实文件 IO 必须放进 tester.runAsync 窗口；
/// 2. AiKeys.load() 是一串多个 IO await，每跳需要"真实窗口推进 IO + pump
///    推进 fake 区续体"交替进行——单窗口推不完，否则加载态转圈不停、
///    pumpAndSettle 永不收敛。
void main() {
  /// 交替开真实时间窗口 + pump，把真实 IO 链条排干。
  Future<void> drain(WidgetTester tester,
      {int rounds = 12, bool Function()? done}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      if (done?.call() ?? false) return;
    }
  }

  testWidgets('解锁 → 配置页可见；填 LLM 密钥 → 状态变真链路；保存 → 落盘',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = PathProviderPlatform.instance;

    final dir = Directory(
        '${Directory.systemTemp.path}/ps_settings_${DateTime.now().millisecondsSinceEpoch}');
    await tester.runAsync(() => dir.create(recursive: true));

    try {
      PathProviderPlatform.instance = _FakePathProvider(dir);
      await tester.pumpWidget(const PaintingSpriteApp());
      await tester.tap(find.text('⚙️'));
      await tester.pump();
      // 排干 SettingsScreen/HomeScreen 两侧 AiKeys.load() 的 IO 链
      await drain(tester);
      await tester.pumpAndSettle();

      // 过算术门：解析 "a + b = ?" 算出答案
      final q = tester
          .widget<Text>(
              find.textContaining(RegExp(r'^\d+ \+ \d+ = \?$')).first)
          .data!;
      final m = RegExp(r'(\d+) \+ (\d+)').firstMatch(q)!;
      await tester.enterText(
          find.byType(TextField), '${int.parse(m.group(1)!) + int.parse(m.group(2)!)}');
      await tester.tap(find.text('解锁'));
      await tester.pump();
      // 配置卡加载态结束（无限动画的转圈消失）才算就绪
      await drain(
        tester,
        rounds: 15,
        done: () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await tester.pumpAndSettle();

      expect(find.text('AI 真链路状态'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: '配置加载应已完成');
      // 卡片标题本身含"真链路"三字，须用带图标的完整芯片文本匹配
      expect(find.textContaining('✅ 真链路'), findsNothing);

      // 展开 LLM 配置区（先滚到可见——ListView 惰性构建 + ExpansionTile 折叠）
      final llmTile = find.text('🧠 愿望理解（LLM，OpenAI 兼容）');
      await tester.ensureVisible(llmTile);
      await tester.pumpAndSettle();
      await tester.tap(llmTile);
      await tester.pumpAndSettle();

      // 填入 LLM 密钥 → 徽章即时变真链路
      final llmField = find.byKey(const Key('llm_api_key_field'));
      await tester.ensureVisible(llmField);
      await tester.pumpAndSettle();
      await tester.enterText(llmField, 'sk-test-123');
      await tester.pump();
      // 状态卡已滚出视口且被 ListView 卸载，负向步进滚回顶部再断言
      await tester.scrollUntilVisible(
        find.text('AI 真链路状态'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      // 状态芯片是单个 Text（如 "✅ 真链路"），必须用包含匹配
      expect(find.textContaining('✅ 真链路'), findsOneWidget);

      // 保存 → 写盘 + 重建 AI 服务（多跳 IO 链，排干直到 SnackBar 出现）
      await tester.scrollUntilVisible(
        find.text('保存'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pump();
      await drain(
        tester,
        rounds: 20,
        done: () => find.textContaining('已保存').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('已保存'), findsOneWidget, reason: '保存应已成功');

      // 验证落盘（真实 IO → runAsync）
      var exists = false;
      var content = '';
      await tester.runAsync(() async {
        final saved = File('${dir.path}/${AiKeys.appOverrideFileName}');
        exists = await saved.exists();
        if (exists) content = await saved.readAsString();
      });
      expect(exists, isTrue, reason: '应用内配置文件应已写入文档目录');
      expect(content, contains('sk-test-123'));
    } finally {
      await tester.runAsync(() async {
        PathProviderPlatform.instance = original;
        if (await dir.exists()) await dir.delete(recursive: true);
      });
    }
  });
}
