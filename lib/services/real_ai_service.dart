import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'package:painting_sprite/services/ai_keys.dart';

/// 真实 AI 实现：豆包 ASR / 图像 + GLM LLM + 可灵视频。
///
/// 每个方法独立降级：对应密钥缺失时抛 [ApiKeyMissingError]，
/// 由调用方（魔法屏/涂色屏）按四级降级策略兜底。
class ApiKeyMissingError implements Exception {
  final String capability;
  ApiKeyMissingError(this.capability);
  @override
  String toString() => '缺少 $capability 的 API 密钥（ai_keys.json）';
}

class RealAiService {
  RealAiService(this.keys, {http.Client? client}) : _client = client ?? http.Client();

  final AiKeys keys;
  final http.Client _client;

  // ---------------- 豆包 ASR ----------------

  /// 音频（wav/m4a）→ 文本。
  Future<String> transcribe(Uint8List audioBytes) async {
    if (!keys.hasAsr) throw ApiKeyMissingError('语音识别');
    final resp = await _client.post(
      Uri.parse('${keys.doubaoBaseUrl}/audio/transcriptions'),
      headers: {'Authorization': 'Bearer ${keys.doubaoApiKey}'},
      body: jsonEncode({
        'model': keys.doubaoAsrModel,
        'audio': base64Encode(audioBytes),
        'format': 'm4a', // 与 HoldToTalk 的 aacLc/.m4a 保持一致
      }),
    ).timeout(const Duration(seconds: 30));
    _throwIfNotOk(resp, 'ASR');
    return jsonDecode(resp.body)['text'] as String? ?? '';
  }

  // ---------------- OpenAI 兼容 LLM（GLM/DeepSeek/Qwen/Ollama…）----------------

  /// 愿望理解：一次调用完成 分类 + 中译英 + 视频提示词。
  Future<({String wish, String videoPrompt})> interpretWish(String text) async {
    if (!keys.hasLlm) throw ApiKeyMissingError('LLM');
    final base = keys.llmBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final resp = await _client.post(
      Uri.parse('$base/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${keys.llmApiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': keys.llmModel,
        'messages': [
          {
            'role': 'system',
            'content': '你是儿童涂鸦App的愿望精灵。孩子会说一句话描述想让'
                '自己的画做什么。请严格输出JSON：{"wish":"dance|fly|sing|run'
                '|jump|other","video_prompt":"<英文视频提示词，儿童友好、'
                '明快色彩、描述主体动作>"}。不要输出任何其他文字。',
          },
          {'role': 'user', 'content': text},
        ],
        'temperature': 0.6,
      }),
    ).timeout(const Duration(seconds: 30));
    _throwIfNotOk(resp, 'LLM');
    final content =
        jsonDecode(resp.body)['choices'][0]['message']['content'] as String;
    return _parseWishJson(content, text);
  }

  ({String wish, String videoPrompt}) _parseWishJson(String content, String raw) {
    try {
      final m = RegExp(r'\{[^{}]*\}').firstMatch(content);
      final j = jsonDecode(m!.group(0)!) as Map<String, dynamic>;
      return (
        wish: (j['wish'] as String?) ?? 'other',
        videoPrompt:
            (j['video_prompt'] as String?) ?? 'a cute doodle dancing happily',
      );
    } catch (_) {
      return (wish: 'other', videoPrompt: 'a cute doodle character comes alive, $raw');
    }
  }

  // ---------------- Seedream 线稿 ----------------

  /// 文本 → 2 张线稿 PNG（孩子二选一）。
  Future<List<Uint8List>> generateLineArt(String subject) async {
    if (!keys.hasImage) throw ApiKeyMissingError('线稿生成');
    final prompt =
        "Children's coloring book page: $subject. Thick black outlines on pure "
        'white background, no shading, no color, simple closed shapes for kids.';
    final results = <Uint8List>[];
    for (var i = 0; i < 2; i++) {
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
          'response_format': 'b64_json',
        }),
      ).timeout(const Duration(seconds: 60));
      _throwIfNotOk(resp, '线稿生成');
      final b64 = jsonDecode(resp.body)['data'][0]['b64_json'] as String;
      results.add(base64Decode(b64));
    }
    return results;
  }

  // ---------------- 可灵图生视频 ----------------

  /// 作品图 + 提示词 → 5 秒 720p 视频 URL（轮询直到完成）。
  Future<Uri> animateToUrl({
    required Uint8List imageBytes,
    required String videoPrompt,
  }) async {
    if (!keys.hasVideo) throw ApiKeyMissingError('视频生成');

    // 1. 建任务
    final create = await _client.post(
      Uri.parse('${keys.klingBaseUrl}/v1/videos/image2video'),
      headers: {
        'Authorization': 'Bearer ${_klingToken()}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model_name': keys.klingVideoModel,
        'image': base64Encode(imageBytes),
        'prompt': videoPrompt,
        'duration': '5',
        'mode': 'std',
      }),
    ).timeout(const Duration(seconds: 30));
    _throwIfNotOk(create, '视频建任务');

    final taskId = jsonDecode(create.body)['data']['task_id'] as String;

    // 2. 轮询（最多 3 分钟，与设计文档超时一致）
    const pollInterval = Duration(seconds: 5);
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
      final st = await _client.get(
        Uri.parse('${keys.klingBaseUrl}/v1/videos/image2video/$taskId'),
        headers: {'Authorization': 'Bearer ${_klingToken()}'},
      ).timeout(const Duration(seconds: 15));
      _throwIfNotOk(st, '视频查询');
      final body = jsonDecode(st.body);
      final status = body['data']['task_status'] as String;
      if (status == 'succeed') {
        final url = body['data']['task_result']['videos'][0]['url'] as String;
        return Uri.parse(url);
      }
      if (status == 'failed') {
        throw Exception('可灵生成失败：${body['data']['task_status_msg']}');
      }
    }
    throw TimeoutException('视频生成超时（3 分钟）');
  }

  /// 图生视频：作品图 + 提示词 → 5 秒视频 URL（轮询直到完成）。
  /// 与 AiService 接口同名同签名，供 FallbackAiService 透传。
  Future<Uri> animateDrawing({
    required Uint8List imageBytes,
    required String videoPrompt,
  }) =>
      animateToUrl(imageBytes: imageBytes, videoPrompt: videoPrompt);

  /// 下载视频字节（存相册用）。
  Future<Uint8List> downloadVideo(Uri url) async {
    final resp = await _client.get(url).timeout(const Duration(seconds: 60));
    _throwIfNotOk(resp, '视频下载');
    return resp.bodyBytes;
  }

  // ---------------- 可灵 JWT ----------------

  String? _cachedToken;
  DateTime? _tokenExp;

  String _klingToken() {
    final halfHourLater = DateTime.now().add(const Duration(minutes: 30));
    if (_cachedToken != null && _tokenExp != null && _tokenExp!.isAfter(halfHourLater)) {
      return _cachedToken!;
    }
    final token = _signKlingJwt(
      ak: keys.klingAccessKey!,
      sk: keys.klingSecretKey!,
    );
    _cachedToken = token;
    _tokenExp = DateTime.now().add(const Duration(minutes: 30));
    return token;
  }

  /// 可灵 JWT：header.payload.signature（HS256）。
  static String _signKlingJwt({required String ak, required String sk}) {
    final b64 = Base64Encoder.urlSafe();
    String enc(Map<String, dynamic> m) =>
        b64.convert(utf8.encode(jsonEncode(m))).replaceAll('=', '');

    final header = enc({'alg': 'HS256', 'typ': 'JWT'});
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final payload = enc({
      'iss': ak,
      'exp': now + 1800,
      'nbf': now - 5,
    });
    final signingInput = '$header.$payload';
    final sig = Hmac(sha256, utf8.encode(sk))
        .convert(utf8.encode(signingInput))
        .bytes;
    final sigB64 = b64.convert(sig).replaceAll('=', '');
    return '$signingInput.$sigB64';
  }

  void _throwIfNotOk(http.Response resp, String tag) {
    if (resp.statusCode >= 300) {
      throw Exception('$tag 失败 [${resp.statusCode}]：${resp.body.substring(0, resp.body.length > 200 ? 200 : resp.body.length)}');
    }
  }
}
