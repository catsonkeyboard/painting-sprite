import 'package:flutter/foundation.dart';

import 'package:painting_sprite/services/ai_keys.dart';
import 'package:painting_sprite/services/ai_service.dart';
import 'package:painting_sprite/services/real_ai_service.dart';
import 'package:painting_sprite/magic/wish_action.dart';

export 'package:painting_sprite/services/ai_service.dart'
    show AnimationCancelled;

/// 降级网关：真实 API 优先，密钥缺失 / 调用失败自动降级。
///
/// 设计文档 §3.4 四级降级阶梯的服务端实现，原则：**降级不造假**——
/// - 无密钥（纯 Mock 模式）：直接 Mock，全功能可玩；
/// - 真链路配置了但失败：把失败如实交给 UI 走下一级阶梯
///   （ASR → 空串触发"再说一遍"；线稿/LLM → 抛异常落内置库/默认提示词），
///   绝不返回伪造的"成功"结果骗孩子；
/// - 粘性降级：连续失败达到阈值后短时间跳过真链路直接 Mock，
///   避免断网时每次都白等满超时（"8 秒耐心"设计）。
class FallbackAiService implements AiService {
  FallbackAiService({required this.real, required this.mock});

  final RealAiService real;
  final MockAiService mock;

  int degradedCount = 0;
  int _failStreak = 0;
  DateTime? _degradedUntil;

  /// 连续失败 N 次进入粘性降级。
  static const int _stickyAfter = 3;

  /// 粘性降级持续时长。
  static const Duration _stickyFor = Duration(minutes: 10);

  /// 任一真链路能力配置了即视为"配置了真链路"（决定降级语义）。
  bool get _realConfigured =>
      real.keys.hasAsr || real.keys.hasImage || real.keys.hasLlm;

  bool get _sticky =>
      _degradedUntil != null && DateTime.now().isBefore(_degradedUntil!);

  void _onRealFailure(String capability, Object e) {
    degradedCount++;
    _failStreak++;
    debugPrint('[$capability] 真链路失败（第 $_failStreak 次）：$e');
    if (_failStreak >= _stickyAfter) {
      _degradedUntil = DateTime.now().add(_stickyFor);
      _failStreak = 0;
      debugPrint('[$capability] 连续失败，进入 ${_stickyFor.inMinutes} 分钟粘性降级');
    }
  }

  void _onRealSuccess() => _failStreak = 0;

  @override
  Future<String> transcribe(Uint8List audioBytes) async {
    if (!_realConfigured || _sticky) return mock.transcribe(audioBytes);
    try {
      final r = await real.transcribe(audioBytes);
      _onRealSuccess();
      return r;
    } catch (e) {
      _onRealFailure('ASR', e);
      // 返回空串 = "没听清"，UI 走"再说一遍 + 预设按钮"，
      // 不返回伪造文本（孩子说小猫却得到恐龙线稿）。
      return '';
    }
  }

  @override
  Future<List<Uint8List>> generateLineArt(String subject) async {
    if (!_realConfigured || _sticky) return mock.generateLineArt(subject);
    try {
      final r = await real.generateLineArt(subject);
      _onRealSuccess();
      return r;
    } catch (e) {
      _onRealFailure('线稿', e);
      // 线稿失败必须落 UI 的内置线稿库兜底（catch 透传），
      // 不能拿 Mock 的 1x1 白图当"生成成功"骗过二选一。
      rethrow;
    }
  }

  @override
  Future<({String wish, String videoPrompt})> interpretWish(String text) async {
    if (!_realConfigured || _sticky) return mock.interpretWish(text);
    try {
      final r = await real.interpretWish(text);
      _onRealSuccess();
      return r;
    } catch (e) {
      _onRealFailure('LLM', e);
      // 抛给魔法屏：它有自己的默认提示词兜底，不需要假结果。
      rethrow;
    }
  }

  /// 视频是"大魔法"：直接透传真实实现。失败抛异常，
  /// UI 层捕获后走本地动画兜底（体验差异太大，假视频骗不了孩子）。
  @override
  Future<Uri> animateDrawing({
    required Uint8List imageBytes,
    required String videoPrompt,
    bool Function()? isCancelled,
  }) {
    return real.animateDrawing(
      imageBytes: imageBytes,
      videoPrompt: videoPrompt,
      isCancelled: isCancelled,
    );
  }

  @override
  Future<Uint8List?> downloadVideoOrNull(Uri url) async {
    try {
      return await real.downloadVideo(url);
    } catch (e) {
      debugPrint('[视频下载] 失败，回退 URL 在线播放：$e');
      return null;
    }
  }

  /// 画作分析兜底（Task 4 实现真逻辑；此处先保证接口编译）。
  @override
  Future<ArtworkAnalysis?> analyzeArtwork(Uint8List pngBytes) async => null;

  /// 便捷工厂：读 ai_keys.json，无密钥时纯 Mock。
  static Future<FallbackAiService> create() async {
    final keys = await AiKeys.load();
    return FallbackAiService(
      real: RealAiService(keys),
      mock: MockAiService(),
    );
  }
}
