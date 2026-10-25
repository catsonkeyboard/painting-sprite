import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:painting_sprite/magic/magic_show.dart';
import 'package:painting_sprite/magic/wish_action.dart';
import 'package:painting_sprite/services/ai_keys.dart';
import 'package:painting_sprite/services/ai_service.dart';
import 'package:painting_sprite/services/real_ai_service.dart';

void main() {
  test('默认动作集恰好 4 个，字段齐全且不与麦克风 emoji 冲突', () {
    final d = ArtworkAnalysis.defaultActions;
    expect(d.length, 4);
    for (final a in d) {
      expect(a.label, isNotEmpty);
      expect(a.emoji, isNotEmpty);
      expect(a.emoji.contains('🎤'), isFalse);
      expect(a.prompt, isNotEmpty);
      expect(WishType.values, contains(a.anim));
    }
  });

  test('默认动作集标签与原四愿望一致（向后兼容现有 UI）', () {
    final labels = ArtworkAnalysis.defaultActions.map((a) => a.label).toList();
    expect(labels, ['跳舞', '飞起来', '唱歌', '奔跑']);
  });

  group('MockAiService.analyzeArtwork', () {
    test('返回通用默认动作集（离线可玩）', () async {
      final mock = MockAiService();
      final a = await mock.analyzeArtwork(Uint8List.fromList([1]));
      expect(a, isNotNull);
      expect(a!.subject, '小精灵');
      expect(a.actions.length, 4);
      expect(mock.callCount, 1);
    });
  });

  group('RealAiService.parseAnalysis', () {
    const ok = '{"subject":"小猫","actions":['
        '{"label":"奔跑","emoji":"🏃","anim":"run","prompt":"a cat running"},'
        '{"label":"打滚","emoji":"🤸","anim":"dance","prompt":"a cat rolling"},'
        '{"label":"跳跃","emoji":"⬆️","anim":"fly","prompt":"a cat jumping"},'
        '{"label":"睡觉","emoji":"😴","anim":"sing","prompt":"a cat sleeping"}]}';

    test('正常 JSON 解析', () {
      final a = RealAiService.parseAnalysis(ok);
      expect(a!.subject, '小猫');
      expect(a.actions.length, 4);
      expect(a.actions.first.label, '奔跑');
      expect(a.actions.first.anim, WishType.run);
    });

    test('动作数 5 → 截前 4', () {
      final five = ok.replaceFirst(
          ']}', ',{"label":"x","emoji":"✨","anim":"run","prompt":"p"}]}');
      expect(RealAiService.parseAnalysis(five)!.actions.length, 4);
    });

    test('动作数 3 → null', () {
      const three = '{"subject":"猫","actions":['
          '{"label":"a","emoji":"✨","anim":"run","prompt":"p"},'
          '{"label":"b","emoji":"✨","anim":"run","prompt":"p"},'
          '{"label":"c","emoji":"✨","anim":"run","prompt":"p"}]}';
      expect(RealAiService.parseAnalysis(three), isNull);
    });

    test('anim 越界丢弃后不足 4 → null', () {
      const badAnim = '{"subject":"猫","actions":['
          '{"label":"a","emoji":"✨","anim":"swim","prompt":"p"},'
          '{"label":"b","emoji":"✨","anim":"run","prompt":"p"},'
          '{"label":"c","emoji":"✨","anim":"run","prompt":"p"},'
          '{"label":"d","emoji":"✨","anim":"run","prompt":"p"}]}';
      expect(RealAiService.parseAnalysis(badAnim), isNull);
    });

    test('垃圾 JSON / 空 prompt → null', () {
      expect(RealAiService.parseAnalysis('不是JSON'), isNull);
      final emptyPrompt =
          ok.replaceAll('"prompt":"a cat running"', '"prompt":" "');
      expect(RealAiService.parseAnalysis(emptyPrompt), isNull);
    });

    test('麦克风 emoji 的动作被丢弃（不足 4 → null）', () {
      final mic = ok.replaceFirst('"emoji":"🏃"', '"emoji":"🎤"');
      expect(RealAiService.parseAnalysis(mic), isNull);
    });

    test('超长 prompt 截断 500', () {
      final long = ok.replaceAll(
          '"prompt":"a cat running"', '"prompt":"${'x' * 600}"');
      final a = RealAiService.parseAnalysis(long)!;
      expect(a.actions.first.prompt.length, 500);
    });
  });

  group('RealAiService.analyzeArtwork（HTTP 行为）', () {
    const okContent = '{"subject":"小猫","actions":['
        '{"label":"奔跑","emoji":"🏃","anim":"run","prompt":"a cat running"},'
        '{"label":"打滚","emoji":"🤸","anim":"dance","prompt":"a cat rolling"},'
        '{"label":"跳跃","emoji":"⬆️","anim":"fly","prompt":"a cat jumping"},'
        '{"label":"睡觉","emoji":"😴","anim":"sing","prompt":"a cat sleeping"}]}';

    test('成功：请求含 image_url base64，返回解析结果', () async {
      String? body;
      final real = RealAiService(
        const AiKeys(
            doubaoApiKey: 'k', doubaoAsrModel: 'doubao-seed-2-1-lite-260915'),
        client: MockClient((req) async {
          body = req.body;
          return http.Response(
              jsonEncode({
                'choices': [
                  {'message': {'content': okContent}}
                ]
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );
      final a = await real.analyzeArtwork(Uint8List.fromList([1, 2]));
      expect(a!.subject, '小猫');
      expect(body, contains('image_url'));
      expect(body, contains('data:image/png;base64,'));
      expect(body, contains('doubao-seed-2-1-lite-260915'));
    });

    test('HTTP 500 → 抛 AiHttpException（由 Fallback 兜底）', () async {
      final real = RealAiService(
        const AiKeys(
            doubaoApiKey: 'k', doubaoAsrModel: 'doubao-seed-2-1-lite-260915'),
        client: MockClient((req) async => http.Response('boom', 500)),
      );
      await expectLater(real.analyzeArtwork(Uint8List.fromList([1])),
          throwsA(isA<AiHttpException>()));
    });
  });
}
