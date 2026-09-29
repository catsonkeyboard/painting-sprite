import 'dart:typed_data';

import 'package:painting_sprite/services/ai_keys.dart';
import 'package:painting_sprite/services/ai_service.dart';
import 'package:painting_sprite/services/real_ai_service.dart';

/// 降级网关：真实 API 优先，密钥缺失 / 调用失败自动落回 Mock。
///
/// 这就是设计文档 §3.4 四级降级阶梯的服务端实现：
/// - 正常：真 API（豆包/GLM/可灵）
/// - 无密钥 / 断网 / 超时 / 生成失败：Mock 兜底，孩子永远看得到结果
class FallbackAiService implements AiService {
  FallbackAiService({required this.real, required this.mock});

  final RealAiService real;
  final MockAiService mock;

  int degradedCount = 0;

  @override
  Future<String> transcribe(Uint8List audioBytes) async {
    try {
      return await real.transcribe(audioBytes);
    } catch (_) {
      degradedCount++;
      return mock.transcribe(audioBytes);
    }
  }

  @override
  Future<List<Uint8List>> generateLineArt(String subject) async {
    try {
      return await real.generateLineArt(subject);
    } catch (_) {
      degradedCount++;
      return mock.generateLineArt(subject);
    }
  }

  @override
  Future<({String wish, String videoPrompt})> interpretWish(String text) async {
    try {
      return await real.interpretWish(text);
    } catch (_) {
      degradedCount++;
      return mock.interpretWish(text);
    }
  }

  /// 视频是"大魔法"：直接透传真实实现。失败抛异常，
  /// UI 层捕获后走本地动画兜底（体验差异太大，假视频骗不了孩子）。
  @override
  Future<Uri> animateDrawing({
    required Uint8List imageBytes,
    required String videoPrompt,
  }) async {
    return real.animateDrawing(imageBytes: imageBytes, videoPrompt: videoPrompt);
  }

  /// 便捷工厂：读 ai_keys.json，无密钥时纯 Mock。
  static Future<FallbackAiService> create() async {
    final keys = await AiKeys.load();
    return FallbackAiService(
      real: RealAiService(keys),
      mock: MockAiService(),
    );
  }
}
