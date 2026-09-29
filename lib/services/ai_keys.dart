import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// AI 配置：优先读 assets/ai_keys.json（Android/iOS 打包进 App），
/// 桌面端回退到可执行文件旁 / 工作目录的 ai_keys.json。
///
/// 无此文件或字段缺失 → 对应能力自动降级 Mock，App 照常可玩。
/// 密钥纪律：ai_keys.json 已 gitignore，绝不提交仓库。
class AiKeys {
  const AiKeys({
    this.doubaoApiKey,
    this.doubaoBaseUrl = 'https://ark.cn-beijing.volces.com/api/v3',
    this.doubaoAsrModel = 'doubao-speech-to-text',
    this.doubaoImageModel = 'doubao-seedream-5-0-pro',
    this.llmApiKey,
    this.llmBaseUrl = 'https://open.bigmodel.cn/api/paas/v4',
    this.llmModel = 'glm-4-flash',
    this.klingAccessKey,
    this.klingSecretKey,
    this.klingBaseUrl = 'https://api.klingai.com',
    this.klingVideoModel = 'kling-v2-6',
  });

  final String? doubaoApiKey;
  final String doubaoBaseUrl;
  final String doubaoAsrModel;
  final String doubaoImageModel;

  /// 任意 OpenAI 兼容的 chat completions 服务
  /// （GLM / DeepSeek / Qwen / 本地 Ollama / vLLM 均可）。
  /// base_url 填到 /v1 或等价前缀，代码自动拼接 /chat/completions。
  final String? llmApiKey;
  final String llmBaseUrl;
  final String llmModel;

  final String? klingAccessKey;
  final String? klingSecretKey;
  final String klingBaseUrl;
  final String klingVideoModel;

  bool get hasAsr => doubaoApiKey != null;
  bool get hasImage => doubaoApiKey != null;
  bool get hasLlm => llmApiKey != null && llmApiKey!.isNotEmpty;
  bool get hasVideo => klingAccessKey != null && klingSecretKey != null;

  /// 加载顺序：assets → 工作目录 → 可执行文件旁。
  static Future<AiKeys> load() async {
    // 1. assets（移动端：密钥文件放进 assets/ 后打包）
    try {
      final s = await rootBundle.loadString('assets/ai_keys.json');
      return _fromJson(s);
    } catch (_) {/* assets 无密钥文件，继续 */}

    // 2. 桌面端：工作目录 / 可执行文件旁
    try {
      for (final base in [
        Directory.current.path,
        Platform.resolvedExecutable,
      ]) {
        final f = File('$base/ai_keys.json');
        if (!await f.exists()) continue;
        return _fromJson(await f.readAsString());
      }
    } catch (e) {
      debugPrint('ai_keys.json 读取失败，全部降级 Mock：$e');
    }
    return const AiKeys();
  }

  static AiKeys _fromJson(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return AiKeys(
      doubaoApiKey: json['doubao_api_key'] as String?,
      doubaoBaseUrl: (json['doubao_base_url'] as String?) ??
          'https://ark.cn-beijing.volces.com/api/v3',
      doubaoAsrModel: (json['doubao_asr_model'] as String?) ?? 'doubao-speech-to-text',
      doubaoImageModel: (json['doubao_image_model'] as String?) ?? 'doubao-seedream-5-0-pro',
      llmApiKey: json['llm_api_key'] as String?,
      llmBaseUrl: (json['llm_base_url'] as String?) ?? 'https://open.bigmodel.cn/api/paas/v4',
      llmModel: (json['llm_model'] as String?) ?? 'glm-4-flash',
      klingAccessKey: json['kling_access_key'] as String?,
      klingSecretKey: json['kling_secret_key'] as String?,
      klingVideoModel: (json['kling_video_model'] as String?) ?? 'kling-v2-6',
    );
  }
}
