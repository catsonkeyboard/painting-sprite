import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// AI 配置：从项目根 `ai_keys.json` 读取（已 gitignore）。
///
/// 无此文件或字段缺失 → 对应能力自动降级 Mock，App 照常可玩。
/// 密钥纪律：绝不提交仓库、绝不上架此包。
class AiKeys {
  const AiKeys({
    this.doubaoApiKey,
    this.doubaoBaseUrl = 'https://ark.cn-beijing.volces.com/api/v3',
    this.doubaoAsrModel = 'doubao-speech-to-text',
    this.doubaoImageModel = 'doubao-seedream-5-0-pro',
    this.zhipuApiKey,
    this.zhipuBaseUrl = 'https://open.bigmodel.cn/api/paas/v4',
    this.klingAccessKey,
    this.klingSecretKey,
    this.klingBaseUrl = 'https://api.klingai.com',
    this.klingVideoModel = 'kling-v2-6',
  });

  final String? doubaoApiKey;
  final String doubaoBaseUrl;
  final String doubaoAsrModel;
  final String doubaoImageModel;

  final String? zhipuApiKey;
  final String zhipuBaseUrl;

  final String? klingAccessKey;
  final String? klingSecretKey;
  final String klingBaseUrl;
  final String klingVideoModel;

  bool get hasAsr => doubaoApiKey != null;
  bool get hasImage => doubaoApiKey != null;
  bool get hasLlm => zhipuApiKey != null;
  bool get hasVideo => klingAccessKey != null && klingSecretKey != null;

  /// 从可执行文件旁或工作目录读 ai_keys.json。
  static Future<AiKeys> load() async {
    try {
      for (final base in [
        Directory.current.path,
        Platform.resolvedExecutable,
      ]) {
        final f = File('$base/ai_keys.json');
        if (!await f.exists()) continue;
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        return AiKeys(
          doubaoApiKey: json['doubao_api_key'] as String?,
          zhipuApiKey: json['zhipu_api_key'] as String?,
          klingAccessKey: json['kling_access_key'] as String?,
          klingSecretKey: json['kling_secret_key'] as String?,
        );
      }
    } catch (e) {
      debugPrint('ai_keys.json 读取失败，全部降级 Mock：$e');
    }
    return const AiKeys();
  }
}
