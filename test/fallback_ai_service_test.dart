import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:painting_sprite/services/ai_keys.dart';
import 'package:painting_sprite/services/ai_service.dart';
import 'package:painting_sprite/services/fallback_ai_service.dart';
import 'package:painting_sprite/services/real_ai_service.dart';

/// 回归：降级网关"降级不造假"语义（修复前 ASR 失败伪造"小恐龙"、
/// 线稿失败返回 1x1 白图骗过二选一）。
void main() {
  final audio = Uint8List.fromList([1, 2, 3]);

  RealAiService failingReal({http.Client? client}) => RealAiService(
        const AiKeys(
          doubaoApiKey: 'test-key',
          doubaoAsrModel: 'ep-test-asr', // 占位值会被半配置守卫拦截
          llmApiKey: 'test-key',
        ),
        client: client,
      );

  test('无密钥 = 纯 Mock 模式，ASR 返回固定文本（可玩性兜底）', () async {
    final fb = FallbackAiService(
      real: RealAiService(const AiKeys()),
      mock: MockAiService(),
    );
    expect(await fb.transcribe(audio), '小恐龙');
  });

  test('真链路 ASR 失败 → 返回空串（不伪造文本），UI 可走"再说一遍"', () async {
    var realCalls = 0;
    final real = failingReal(client: MockClient((req) async {
      realCalls++;
      return http.Response('boom', 500);
    }));
    final fb = FallbackAiService(real: real, mock: MockAiService());

    expect(await fb.transcribe(audio), '');
    expect(realCalls, 1);
    expect(fb.degradedCount, 1);
  });

  test('真链路线稿失败 → 异常透传（UI 落内置线稿库，不给白图）', () async {
    final real = failingReal(client: MockClient((req) async => http.Response('boom', 500)));
    final fb = FallbackAiService(real: real, mock: MockAiService());

    await expectLater(fb.generateLineArt('挖掘机'), throwsException);
  });

  test('真链路 LLM 失败 → 异常透传（魔法屏用默认提示词兜底）', () async {
    final real = failingReal(client: MockClient((req) async => http.Response('boom', 500)));
    final fb = FallbackAiService(real: real, mock: MockAiService());

    await expectLater(fb.interpretWish('跳舞'), throwsException);
  });

  test('粘性降级：连续 3 次失败后跳过真链路直接 Mock', () async {
    var realCalls = 0;
    final real = failingReal(client: MockClient((req) async {
      realCalls++;
      return http.Response('boom', 500);
    }));
    final fb = FallbackAiService(real: real, mock: MockAiService());

    // 三次失败（第三个失败触发粘性降级）
    for (var i = 0; i < 3; i++) {
      await fb.transcribe(audio);
    }
    expect(realCalls, 3);

    // 第四次：不再打真链路，直接 Mock 文本
    expect(await fb.transcribe(audio), '小恐龙');
    expect(realCalls, 3, reason: '粘性降级期间不应再请求真链路');
  });

  test('视频下载尽力而为：失败返回 null 不抛', () async {
    final real = failingReal(client: MockClient((req) async => http.Response('boom', 500)));
    final fb = FallbackAiService(real: real, mock: MockAiService());

    expect(
      await fb.downloadVideoOrNull(Uri.parse('https://example.com/v.mp4')),
      isNull,
    );
  });

  // ---- 方舟 Seedance 视频任务流（一套 Key 方案）----

  test('音频理解转写：chat/completions + input_audio → 提取文本', () async {
    final real = RealAiService(
      const AiKeys(
        doubaoApiKey: 'ark-k',
        doubaoAsrModel: 'doubao-seed-2-1-lite-260915',
      ),
      client: MockClient((req) async => http.Response(
          '{"choices":[{"message":{"content":"我要画小恐龙"}}]}', 200,
          headers: {'content-type': 'application/json; charset=utf-8'})),
    );
    expect(await real.transcribe(Uint8List.fromList([1, 2, 3])), '我要画小恐龙');
  });

  http.Client arkVideoClient({String finalStatus = 'succeeded'}) {
    return MockClient((req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/contents/generations/tasks')) {
        return http.Response('{"id": "cgt-1", "status": "queued"}', 200);
      }
      if (req.method == 'GET' && req.url.path.contains('/tasks/cgt-1')) {
        if (finalStatus == 'succeeded') {
          return http.Response(
              '{"id": "cgt-1", "status": "succeeded", "content": {"video_url": "https://cdn.example.com/v.mp4"}}',
              200);
        }
        // http.Response 默认 latin1 编码，含中文须显式声明 utf-8
        return http.Response(
            '{"id": "cgt-1", "status": "$finalStatus", "error": {"message": "内容审核未通过"}}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('not found', 404);
    });
  }

  test('Seedance 图生视频：建任务 → 轮询 → 拿 video_url', () async {
    final real = RealAiService(
      const AiKeys(doubaoApiKey: 'ark-k'),
      client: arkVideoClient(),
    );
    final uri = await real.animateToUrl(
      imageBytes: Uint8List.fromList([1, 2, 3]),
      videoPrompt: 'a cat dancing',
      pollInterval: const Duration(milliseconds: 5),
    );
    expect(uri.toString(), 'https://cdn.example.com/v.mp4');
  });

  test('Seedance 任务 failed：抛出带原因的异常（UI 落本地动画兜底）', () async {
    final real = RealAiService(
      const AiKeys(doubaoApiKey: 'ark-k'),
      client: arkVideoClient(finalStatus: 'failed'),
    );
    await expectLater(
      real.animateToUrl(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        videoPrompt: 'a cat dancing',
        pollInterval: const Duration(milliseconds: 5),
      ),
      throwsA(isA<AiHttpException>().having((e) => e.detail, 'detail', contains('内容审核'))),
    );
  });

  test('Seedance 轮询取消：isCancelled 为 true 时中止', () async {
    final real = RealAiService(
      const AiKeys(doubaoApiKey: 'ark-k'),
      client: arkVideoClient(),
    );
    await expectLater(
      real.animateToUrl(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        videoPrompt: 'a cat dancing',
        pollInterval: const Duration(milliseconds: 5),
        isCancelled: () => true,
      ),
      throwsA(isA<AnimationCancelled>()),
    );
  });
}
