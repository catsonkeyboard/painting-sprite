import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// AI 配置：火山方舟一个 Key 通吃四个能力（ASR / Seedream 线稿 /
/// Seedance 视频 / 可选豆包 LLM）。
///
/// LLM 插槽保持 OpenAI 兼容可插拔：`llm_api_key` 留空时自动复用豆包 Key
/// 并指向方舟豆包模型；也可显式指向智谱 / DeepSeek / 本地 Ollama 等。
///
/// 加载顺序：应用内家长配置 → assets → 工作目录 → 可执行文件旁。
/// 无配置 → 全能力自动降级 Mock，App 照常可玩。
/// 密钥纪律：ai_keys.json 已 gitignore，绝不提交仓库。
class AiKeys {
  const AiKeys({
    this.doubaoApiKey,
    this.doubaoBaseUrl = 'https://ark.cn-beijing.volces.com/api/v3',
    this.doubaoAsrModel = 'doubao-seed-2-1-lite-260915',
    this.doubaoImageModel = 'doubao-seedream-5-0-flash-260915',
    this.doubaoVideoModel = 'doubao-seedance-2-0-mini-260615',
    this.llmApiKey,
    this.llmBaseUrl = '',
    this.llmModel = '',
  });

  final String? doubaoApiKey;
  final String doubaoBaseUrl;
  final String doubaoAsrModel;
  final String doubaoImageModel;

  /// 方舟 Seedance 视频模型（图生视频）。
  final String doubaoVideoModel;

  /// OpenAI 兼容 LLM 插槽（可留空回落豆包）。
  final String? llmApiKey;
  final String llmBaseUrl;
  final String llmModel;

  // ---- 生效规则 ----

  /// 空字符串视为未配置（example 模板默认值是 ""，照抄不填
  /// 不应该发起注定 401 的真请求）。
  bool get hasAsr => _ok(doubaoApiKey) && _asrModelConfigured;
  bool get hasImage => _ok(doubaoApiKey);
  bool get hasVideo => _ok(doubaoApiKey);

  /// ASR 半配置守卫：旧模板的占位值（方舟上不存在此模型）按未配置处理。
  /// 语音识别走方舟「音频理解」，此字段填支持音频输入的多模态豆包模型。
  static const String asrModelPlaceholder = 'doubao-speech-to-text';

  bool get _asrModelConfigured =>
      doubaoAsrModel.trim().isNotEmpty &&
      doubaoAsrModel.trim() != asrModelPlaceholder;

  /// LLM 是否复用豆包 Key：未独立配置 llm_api_key，且 base 未显式指向
  /// 其他厂商（避免把方舟 Key 发给 DeepSeek 之类的误配置）。
  bool get _llmUsesDoubaoKey {
    if (_ok(llmApiKey) || !_ok(doubaoApiKey)) return false;
    final b = llmBaseUrl.trim();
    return b.isEmpty || b.contains('volces.com');
  }

  String? get llmApiKeyEffective {
    if (_ok(llmApiKey)) return llmApiKey;
    return _llmUsesDoubaoKey ? doubaoApiKey : null;
  }

  bool get hasLlm => _ok(llmApiKeyEffective);

  /// base：显式配置优先；否则跟随 Key 来源（豆包 → 方舟 / 默认智谱）。
  String get llmBaseUrlEffective {
    final b = llmBaseUrl.trim();
    if (b.isNotEmpty) return b;
    return _llmUsesDoubaoKey
        ? doubaoBaseUrl
        : 'https://open.bigmodel.cn/api/paas/v4';
  }

  /// 模型：显式配置优先；跟随豆包 Key 时用豆包模型，否则默认 GLM 免费档。
  String get llmModelEffective {
    final m = llmModel.trim();
    if (m.isNotEmpty) return m;
    return _llmUsesDoubaoKey ? 'doubao-seed-2-1-lite-260915' : 'glm-4-flash';
  }

  static bool _ok(String? s) => s != null && s.isNotEmpty;

  // ---- 持久化 ----

  /// 加载顺序：应用内家长配置 → assets → 工作目录 → 可执行文件旁。
  /// 应用内配置存文档目录（家长设置页写入），优先级最高，
  /// 改密钥/模型无需重新打包。
  static const String appOverrideFileName = 'ai_keys_app.json';

  static Future<File> _overrideFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$appOverrideFileName');
  }

  /// 保存应用内配置（家长设置页调用）。
  static Future<void> saveAppOverride(AiKeys keys) async {
    final f = await _overrideFile();
    await f.writeAsString(jsonEncode(keys.toJson()), flush: true);
  }

  /// 清除应用内配置 → 回落到 assets / 根目录文件配置。
  static Future<void> clearAppOverride() async {
    final f = await _overrideFile();
    if (await f.exists()) await f.delete();
  }

  static Future<AiKeys> load() async {
    // 0. 应用内家长配置（最高优先级）
    try {
      final f = await _overrideFile();
      if (await f.exists()) return fromJson(await f.readAsString());
    } catch (e) {
      debugPrint('$appOverrideFileName 读取失败（忽略）：$e');
    }

    // 1. assets（移动端：密钥文件放进 assets/ 后打包）
    try {
      final s = await rootBundle.loadString('assets/ai_keys.json');
      return fromJson(s);
    } catch (_) {/* assets 无密钥文件，继续 */}

    // 2. 桌面端：工作目录 / 可执行文件旁
    try {
      for (final base in [
        Directory.current.path,
        // resolvedExecutable 是可执行文件全路径，须取其所在目录
        File(Platform.resolvedExecutable).parent.path,
      ]) {
        final f = File('$base/ai_keys.json');
        if (!await f.exists()) continue;
        return fromJson(await f.readAsString());
      }
    } catch (e) {
      debugPrint('ai_keys.json 读取失败，全部降级 Mock：$e');
    }
    return const AiKeys();
  }

  static AiKeys fromJson(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json.containsKey('kling_access_key') || json.containsKey('kling_secret_key')) {
      debugPrint('AiKeys: 检测到 kling_* 配置——视频生成已切换到方舟 Seedance，'
          '可灵字段已忽略（可从配置中删除）。');
    }
    final keys = AiKeys(
      doubaoApiKey: _nonEmpty(json['doubao_api_key']),
      doubaoBaseUrl: (json['doubao_base_url'] as String?) ??
          'https://ark.cn-beijing.volces.com/api/v3',
      doubaoAsrModel: (json['doubao_asr_model'] as String?) ??
          'doubao-seed-2-1-lite-260915',
      doubaoImageModel: (json['doubao_image_model'] as String?) ??
          'doubao-seedream-5-0-flash-260915',
      doubaoVideoModel: (json['doubao_video_model'] as String?) ??
          'doubao-seedance-2-0-mini-260615',
      llmApiKey: _nonEmpty(json['llm_api_key']),
      llmBaseUrl: (json['llm_base_url'] as String?) ?? '',
      llmModel: (json['llm_model'] as String?) ?? '',
    );
    if (keys.doubaoApiKey != null && !keys._asrModelConfigured) {
      debugPrint('AiKeys: doubao_api_key 已配置但 doubao_asr_model 是旧占位值，'
          'ASR 按未配置处理（Mock）。请填入支持音频输入的多模态豆包模型'
          '（默认 doubao-seed-2-1-lite）或控制台确切模型 ID。');
    }
    return keys;
  }

  Map<String, dynamic> toJson() => {
        'doubao_api_key': doubaoApiKey ?? '',
        'doubao_base_url': doubaoBaseUrl,
        'doubao_asr_model': doubaoAsrModel,
        'doubao_image_model': doubaoImageModel,
        'doubao_video_model': doubaoVideoModel,
        'llm_api_key': llmApiKey ?? '',
        'llm_base_url': llmBaseUrl,
        'llm_model': llmModel,
      };

  static String? _nonEmpty(Object? v) {
    final s = v as String?;
    return (s == null || s.isEmpty) ? null : s;
  }
}
