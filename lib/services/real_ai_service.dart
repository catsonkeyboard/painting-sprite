import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:painting_sprite/services/ai_keys.dart';
import 'package:painting_sprite/services/ai_service.dart' show AnimationCancelled;
import 'package:painting_sprite/magic/magic_show.dart';
import 'package:painting_sprite/magic/wish_action.dart';

/// 真实 AI 实现：火山方舟一个 Key 全链路
/// （豆包 ASR / Seedream 线稿 / Seedance 视频 / OpenAI 兼容 LLM）。
///
/// 每个方法独立降级：对应密钥缺失时抛 [ApiKeyMissingError]，
/// 由调用方（魔法屏/涂色屏）按四级降级策略兜底。
class ApiKeyMissingError implements Exception {
  final String capability;
  ApiKeyMissingError(this.capability);
  @override
  String toString() => '缺少 $capability 的 API 密钥（ai_keys.json）';
}

/// HTTP 层失败（4xx/5xx/业务失败），带状态码便于上层分类处理。
class AiHttpException implements Exception {
  AiHttpException(this.tag, this.status, this.detail);
  final String tag;
  final int status;
  final String detail;

  bool get isAuthError => status == 401 || status == 403;
  bool get isRateLimit => status == 429;

  @override
  String toString() => '$tag 失败 [$status]：$detail';
}

class RealAiService {
  RealAiService(this.keys, {http.Client? client}) : _client = client ?? http.Client();

  final AiKeys keys;
  final http.Client _client;

  // ---------------- 语音识别（方舟音频理解）----------------

  /// 音频（m4a）→ 文本。
  ///
  /// 走方舟「音频理解」：chat/completions + input_audio（base64 内联），
  /// 用普通方舟 Key 和支持音频输入的豆包多模态模型——独立 ASR 模型
  /// （doubao-asr 系列）需要语音专属 UUID Key 且要求音频有公网 URL，
  /// 无后端客户端场景不适用。
  Future<String> transcribe(Uint8List audioBytes) async {
    if (!keys.hasAsr) throw ApiKeyMissingError('语音识别');
    final resp = await _client.post(
      Uri.parse('${keys.doubaoBaseUrl}/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${keys.doubaoApiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': keys.doubaoAsrModel,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': '逐字转写这段儿童语音，只输出转写文本，'
                    '不要任何解释、翻译或标点补充。',
              },
              {
                'type': 'input_audio',
                'input_audio': {
                  'data': base64Encode(audioBytes),
                  'format': 'audio/mp4', // m4a 容器
                },
              },
            ],
          },
        ],
        'thinking': {'type': 'disabled'},
      }),
    ).timeout(const Duration(seconds: 30));
    _throwIfNotOk(resp, 'ASR');
    final content = jsonDecode(resp.body)['choices'][0]['message']['content'];
    if (content is String) return content.trim();
    if (content is List) {
      // 兼容分段 content：取所有 text 段拼接
      return content
          .whereType<Map>()
          .where((c) => c['type'] == 'text')
          .map((c) => (c['text'] ?? '').toString())
          .join()
          .trim();
    }
    return '';
  }

  // ---------------- OpenAI 兼容 LLM（默认回落豆包 / GLM/DeepSeek/Qwen/Ollama…）----------------

  /// 愿望理解：一次调用完成 分类 + 中译英 + 视频提示词。
  ///
  /// 分类白名单与本地动画的 4 种 [WishType] 一一对应，
  /// 避免 LLM 输出无映射的类型被静默当成跳舞。
  Future<({String wish, String videoPrompt})> interpretWish(String text) async {
    if (!keys.hasLlm) throw ApiKeyMissingError('LLM');
    final base = keys.llmBaseUrlEffective.replaceAll(RegExp(r'/+$'), '');
    final body = <String, dynamic>{
      'model': keys.llmModelEffective,
      'messages': [
        {
          'role': 'system',
          'content': '你是儿童涂鸦App的愿望精灵。孩子会说一句话描述想让'
              '自己的画做什么。请严格输出JSON：{"wish":"dance|fly|sing|run'
              '|other","video_prompt":"<英文视频提示词，儿童友好、'
              '明快色彩、描述主体动作，不超过60词>"}。不要输出任何其他文字。',
        },
        {'role': 'user', 'content': text},
      ],
      'temperature': 0.6,
    };
    // 豆包 Seed 系列默认启用深度思考——愿望分类用不上，关掉省时省钱
    if (base.contains('volces.com')) {
      body['thinking'] = {'type': 'disabled'};
    }
    final resp = await _client.post(
      Uri.parse('$base/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${keys.llmApiKeyEffective}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));
    _throwIfNotOk(resp, 'LLM');
    final content =
        jsonDecode(resp.body)['choices'][0]['message']['content'] as String;
    return _parseWishJson(content);
  }

  static const _wishWhitelist = {'dance', 'fly', 'sing', 'run', 'other'};

  ({String wish, String videoPrompt}) _parseWishJson(String content) {
    try {
      final m = RegExp(r'\{[^{}]*\}').firstMatch(content);
      final j = jsonDecode(m!.group(0)!) as Map<String, dynamic>;
      final wish = (j['wish'] as String?)?.trim().toLowerCase() ?? 'other';
      // 输出长度截断：视频模型 prompt 有上限，超长只会被拒
      final prompt = ((j['video_prompt'] as String?) ?? '')
          .replaceAll(RegExp(r'[\r\n]+'), ' ')
          .trim();
      if (prompt.isEmpty) throw const FormatException('empty video_prompt');
      return (
        wish: _wishWhitelist.contains(wish) ? wish : 'other',
        videoPrompt: prompt.length > 500 ? prompt.substring(0, 500) : prompt,
      );
    } catch (_) {
      // 解析失败用固定兜底提示词（不拼接孩子的原文，防注入且提示词质量可控）
      return (
        wish: 'other',
        videoPrompt: 'a cute doodle character dancing happily, '
            'playful children animation style',
      );
    }
  }

  // ---------------- 画作分析（多模态视觉）----------------

  /// 画作 PNG → (主体, 4 个推荐动作)。
  ///
  /// 与 ASR 同一个多模态模型（一套 Key）；HTTP 错误抛 [AiHttpException]，
  /// 模型返回内容不合法返回 null（UI 落默认按钮）。
  Future<ArtworkAnalysis?> analyzeArtwork(Uint8List pngBytes) async {
    if (!keys.hasAsr) throw ApiKeyMissingError('画作分析');
    final resp = await _client.post(
      Uri.parse('${keys.doubaoBaseUrl}/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${keys.doubaoApiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': keys.doubaoAsrModel,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': '看这张儿童涂鸦。严格输出JSON（不要任何其他文字）：'
                    '{"subject":"<画的是什么，中文2-4字>",'
                    '"actions":[{"label":"<动作中文2-3字>","emoji":"<单个表情>",'
                    '"anim":"dance|fly|sing|run","prompt":"<英文视频提示词，'
                    '儿童友好、明快色彩、以画的主体为主语，不超过40词>"}]}。'
                    'actions 恰好 4 个，必须贴合所画主体的习性（如金鱼→游泳，'
                    '火箭→升空）；emoji 不要用 🎤；anim 是等待期动画类型：'
                    '摇摆类选 dance、飘浮/上升类选 fly、节奏/声音类选 sing、'
                    '移动类选 run。',
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/png;base64,${base64Encode(pngBytes)}',
                },
              },
            ],
          },
        ],
        'thinking': {'type': 'disabled'},
      }),
    ).timeout(const Duration(seconds: 20));
    _throwIfNotOk(resp, '画作分析');
    final content = jsonDecode(resp.body)['choices'][0]['message']['content'];
    if (content is! String) return null;
    return parseAnalysis(content);
  }

  /// 解析并校验模型输出；任何不合法 → null（降级不造假）。
  static ArtworkAnalysis? parseAnalysis(String content) {
    try {
      final m = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      final j = jsonDecode(m!.group(0)!) as Map<String, dynamic>;
      final subject = (j['subject'] as String?)?.trim();
      if (subject == null || subject.isEmpty) return null;
      final rawActions = j['actions'];
      if (rawActions is! List || rawActions.isEmpty) return null;

      final actions = <WishAction>[];
      for (final e in rawActions.take(4)) {
        if (e is! Map) continue;
        final label = (e['label'] as String?)?.trim() ?? '';
        var emoji = (e['emoji'] as String?)?.trim() ?? '';
        final prompt = ((e['prompt'] as String?) ?? '')
            .replaceAll(RegExp(r'[\r\n]+'), ' ')
            .trim();
        final anim = switch (e['anim'] as String?) {
          'dance' => WishType.dance,
          'fly' => WishType.fly,
          'sing' => WishType.sing,
          'run' => WishType.run,
          _ => null,
        };
        // emoji 只保留短串：截掉模型可能输出的多余文字
        if (emoji.length > 8) emoji = emoji.substring(0, 8);
        if (label.isEmpty || prompt.isEmpty || anim == null) continue;
        if (emoji.isEmpty || emoji.contains('🎤')) continue;
        actions.add(WishAction(
          label: label,
          emoji: emoji,
          prompt: prompt.length > 500 ? prompt.substring(0, 500) : prompt,
          anim: anim,
        ));
      }
      if (actions.length != 4) return null; // 恒 4 个，不足即整体失败
      return ArtworkAnalysis(subject: subject, actions: actions);
    } catch (_) {
      return null;
    }
  }

  // ---------------- Seedream 线稿 ----------------

  /// 文本 → 2 张线稿 PNG（孩子二选一）。两张并行生成，等待时间减半。
  Future<List<Uint8List>> generateLineArt(String subject) async {
    if (!keys.hasImage) throw ApiKeyMissingError('线稿生成');
    final prompt =
        "Children's coloring book page: $subject. Thick black outlines on pure "
        'white background, no shading, no color, simple closed shapes for kids.';
    final results = await Future.wait([
      _generateOneLineArt(prompt),
      _generateOneLineArt(prompt),
    ]);
    return results;
  }

  Future<Uint8List> _generateOneLineArt(String prompt) async {
    final resp = await _client.post(
      Uri.parse('${keys.doubaoBaseUrl}/images/generations'),
      headers: {
        'Authorization': 'Bearer ${keys.doubaoApiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': keys.doubaoImageModel,
        'prompt': prompt,
        'size': '1024x1024',
        'response_format': 'b64_json', // 直接内联字节，省一次下载
        'watermark': false, // 涂色线稿不要水印
      }),
    ).timeout(const Duration(seconds: 60));
    _throwIfNotOk(resp, '线稿生成');
    final b64 = jsonDecode(resp.body)['data'][0]['b64_json'] as String;
    return base64Decode(b64);
  }

  // ---------------- Seedance 图生视频（方舟任务接口）----------------

  /// 作品图 + 提示词 → 5 秒 720p 视频 URL（建任务 + 轮询）。
  ///
  /// [isCancelled] 每轮轮询前检查：返回 true 立即抛 [AnimationCancelled]
  /// （用户退出魔法屏 / 发起新许愿时停止浪费轮询）。
  /// [pollInterval] 仅供测试注入。
  Future<Uri> animateToUrl({
    required Uint8List imageBytes,
    required String videoPrompt,
    bool Function()? isCancelled,
    Duration pollInterval = const Duration(seconds: 5),
  }) async {
    if (!keys.hasVideo) throw ApiKeyMissingError('视频生成');

    // 1. 建任务：首帧图生视频（图 base64 data URI，不带 role = 首帧）
    //    参数：text 内联 flag 优先级高于顶层参数（官方文档），resolution/ratio
    //    用内联；generate_audio/duration/watermark 用顶层（官方示例确认支持）。
    final create = await _client.post(
      Uri.parse('${keys.doubaoBaseUrl}/contents/generations/tasks'),
      headers: {
        'Authorization': 'Bearer ${keys.doubaoApiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': keys.doubaoVideoModel,
        'content': [
          {
            'type': 'text',
            'text': '$videoPrompt --resolution 720p --ratio adaptive',
          },
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/png;base64,${base64Encode(imageBytes)}',
            },
          },
        ],
        'generate_audio': true, // 音画同生：小恐龙会叫（设计核心体验；成本约翻倍，可改 false 关闭）
        'duration': 5,
        'watermark': false,
      }),
    ).timeout(const Duration(seconds: 30));
    _throwIfNotOk(create, '视频建任务');
    final taskId = (jsonDecode(create.body) as Map<String, dynamic>)['id'] as String?;
    debugPrint('[视频] 建任务成功 id=$taskId model=${keys.doubaoVideoModel}');
    if (taskId == null || taskId.isEmpty) {
      throw AiHttpException('视频建任务', create.statusCode, '响应缺少任务 id');
    }

    // 2. 轮询（最多 3 分钟，与设计文档超时一致）
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() ?? false) throw AnimationCancelled();
      await Future<void>.delayed(pollInterval);
      final st = await _client.get(
        Uri.parse('${keys.doubaoBaseUrl}/contents/generations/tasks/$taskId'),
        headers: {'Authorization': 'Bearer ${keys.doubaoApiKey}'},
      ).timeout(const Duration(seconds: 15));
      _throwIfNotOk(st, '视频查询');
      final body = jsonDecode(st.body);
      if (body is! Map<String, dynamic>) {
        throw AiHttpException('视频查询', st.statusCode, '响应不是 JSON 对象');
      }
      final status = body['status'] as String?;
      debugPrint('[视频] 轮询 status=$status');
      if (status == 'succeeded') {
        final content = body['content'];
        final url = content is Map ? content['video_url'] as String? : null;
        if (url == null || url.isEmpty) {
          throw AiHttpException('视频查询', st.statusCode, '任务成功但缺少 video_url');
        }
        return Uri.parse(url);
      }
      if (status == 'failed' || status == 'cancelled') {
        final err = body['error'];
        final msg = err is Map
            ? (err['message'] ?? '').toString()
            : (err?.toString() ?? status ?? 'unknown');
        throw AiHttpException('视频生成', -1, msg);
      }
      // queued / running → 继续等
    }
    throw TimeoutException('视频生成超时（3 分钟）');
  }

  /// 图生视频：作品图 + 提示词 → 5 秒视频 URL（轮询直到完成）。
  /// 与 AiService 接口同名同签名，供 FallbackAiService 透传。
  Future<Uri> animateDrawing({
    required Uint8List imageBytes,
    required String videoPrompt,
    bool Function()? isCancelled,
  }) =>
      animateToUrl(
        imageBytes: imageBytes,
        videoPrompt: videoPrompt,
        isCancelled: isCancelled,
      );

  /// 下载视频字节（存相册用；方舟 video_url 有时效，必须及时下载）。
  Future<Uint8List> downloadVideo(Uri url) async {
    final resp = await _client.get(url).timeout(const Duration(seconds: 60));
    _throwIfNotOk(resp, '视频下载');
    return resp.bodyBytes;
  }

  void _throwIfNotOk(http.Response resp, String tag) {
    if (resp.statusCode >= 300) {
      final snippet = resp.body.length > 200
          ? resp.body.substring(0, 200)
          : resp.body;
      throw AiHttpException(tag, resp.statusCode, snippet);
    }
  }
}
