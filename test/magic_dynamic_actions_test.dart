import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:painting_sprite/magic/magic_show.dart';
import 'package:painting_sprite/magic/wish_action.dart';
import 'package:painting_sprite/screens/magic_screen.dart';
import 'package:painting_sprite/services/ai_service.dart';
import 'package:painting_sprite/services/speech_service.dart';

/// 可编程 Mock：分析结果可注入。
class _FakeAi implements AiService {
  _FakeAi(this.analysis);
  final ArtworkAnalysis? analysis;
  int analyzeCalls = 0;
  String? lastVideoPrompt;

  @override
  Future<ArtworkAnalysis?> analyzeArtwork(Uint8List pngBytes) async {
    analyzeCalls++;
    return analysis;
  }

  @override
  Future<String> transcribe(Uint8List audioBytes) async => '跳舞';

  @override
  Future<List<Uint8List>> generateLineArt(String subject) async => [];

  @override
  Future<({String wish, String videoPrompt})> interpretWish(String text,
      {String? subject}) async {
    return (wish: 'dance', videoPrompt: 'llm prompt');
  }

  @override
  Future<Uri> animateDrawing({
    required Uint8List imageBytes,
    required String videoPrompt,
    bool Function()? isCancelled,
  }) async {
    lastVideoPrompt = videoPrompt;
    throw MockVideoDegraded(); // 直接落兜底，测试不依赖视频
  }

  @override
  Future<Uint8List?> downloadVideoOrNull(Uri url) async => null;
}

/// 合法的 1x1 白色 PNG（Image.memory 需要可解码数据）。
final _tinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
  0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE,
  0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63,
  0xF8, 0xCF, 0xC0, 0x00, 0x00, 0x00, 0x03, 0x00, 0x01, 0x5D, 0xDE,
  0x7C, 0x89, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

Widget _wrap(AiService ai) => MaterialApp(
      home: MagicScreen(
        pngBytes: _tinyPng,
        ai: ai,
        speech: FakeSpeechService(),
      ),
    );

const _fishActions = ArtworkAnalysis(subject: '金鱼', actions: [
  WishAction(
      label: '游泳', emoji: '🏊', prompt: 'a fish swimming', anim: WishType.fly),
  WishAction(
      label: '吐泡泡', emoji: '🫧', prompt: 'bubble', anim: WishType.sing),
  WishAction(label: '摇摆', emoji: '🐟', prompt: 'wiggle', anim: WishType.dance),
  WishAction(label: '冲刺', emoji: '💨', prompt: 'dash', anim: WishType.run),
]);

void main() {
  testWidgets('进屏先渲染默认四按钮，分析失败保默认', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ai = _FakeAi(null); // 分析失败
    await tester.pumpWidget(_wrap(ai));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('🕺'), findsOneWidget);
    expect(find.text('🏃'), findsOneWidget);
    expect(ai.analyzeCalls, 1);
  });

  testWidgets('分析结果到达 → 按钮替换为动态动作', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ai = _FakeAi(_fishActions);
    await tester.pumpWidget(_wrap(ai));
    expect(find.text('🏊'), findsNothing); // 默认按钮先行
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('🏊'), findsOneWidget);
    expect(find.text('🏃'), findsNothing, reason: '默认按钮应被替换');
  });

  testWidgets('点击动态按钮 → 用预生成提示词施法（零 LLM）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ai = _FakeAi(_fishActions);
    await tester.pumpWidget(_wrap(ai));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('🏊'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(ai.lastVideoPrompt, 'a fish swimming');
  });

  testWidgets('内置线稿（knownSubject）：进屏首帧即预制按钮，零分析调用', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ai = _FakeAi(_fishActions);
    await tester.pumpWidget(MaterialApp(
      home: MagicScreen(
        pngBytes: _tinyPng,
        ai: ai,
        speech: FakeSpeechService(),
        knownSubject: '金鱼',
      ),
    ));
    // 不给分析时间：首帧就应显示预制动作
    await tester.pump();
    expect(find.text('游泳'), findsOneWidget);
    expect(find.text('吐泡泡'), findsOneWidget);
    expect(ai.analyzeCalls, 0, reason: '预制集命中时不应调用 LLM 看图');
  });
}
