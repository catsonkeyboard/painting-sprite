import 'dart:typed_data';

import 'package:painting_sprite/magic/wish_action.dart';

/// AI 服务抽象：W2/W3 的所有云端能力挂在下面，实现可插拔
/// （Mock 用于开发测试；正式实现读 ai_keys.json 直连厂商 API）。
///
/// 密钥纪律：ai_keys.json 已 gitignore，绝不提交仓库。
abstract class AiService {
  /// 语音识别：音频 → 文本（孩子说"我要小恐龙"）。
  /// 失败返回空串（而非伪造文本），让 UI 走"再说一遍"兜底。
  Future<String> transcribe(Uint8List audioBytes);

  /// 线稿生成：文本 → 线稿 PNG（生成 2 张供孩子二选一）。
  /// 失败抛异常，UI 捕获后落内置线稿库。
  Future<List<Uint8List>> generateLineArt(String subject);

  /// 愿望理解：文本 → (愿望类型, 英文视频提示词)。
  /// [subject] 为画作主体（画作分析结果），注入提示词提升出片贴合度。
  Future<({String wish, String videoPrompt})> interpretWish(String text,
      {String? subject});

  /// 画作分析：PNG → (主体, 4 个推荐动作)。
  /// 返回 null = 失败/不支持（UI 落默认按钮；不造假数据）。
  Future<ArtworkAnalysis?> analyzeArtwork(Uint8List pngBytes);

  /// 图生视频：作品图 + 提示词 → 动画视频 URL（UI 层播放）。
  /// [isCancelled] 轮询期间定期检查，返回 true 时抛 [AnimationCancelled]。
  Future<Uri> animateDrawing({
    required Uint8List imageBytes,
    required String videoPrompt,
    bool Function()? isCancelled,
  });

  /// 尽力下载视频字节（相册本地保存用，避免云端 URL 过期）。
  /// 失败返回 null（不抛异常），调用方回退 URL 在线播放。
  Future<Uint8List?> downloadVideoOrNull(Uri url);
}

/// 用户取消等待（退出页面 / 发起新许愿）：轮询中止。
class AnimationCancelled implements Exception {
  @override
  String toString() => '动画等待已取消';
}

/// Mock 视频故意降级：UI 捕获后走本地动画兜底
/// （类型安全，替代魔法字符串异常）。
class MockVideoDegraded implements Exception {
  @override
  String toString() => '__mock_video_degraded__';
}

/// 开发/测试 Mock：全链路可跑，零 API 花费。
///
/// W2 涂色链路用 [generateLineArt] 的占位图即可跑通 UI；
/// W3 接入真实 API 时换掉实现类即可。
class MockAiService implements AiService {
  int callCount = 0;

  @override
  Future<String> transcribe(Uint8List audioBytes) async {
    callCount++;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return '小恐龙';
  }

  @override
  Future<List<Uint8List>> generateLineArt(String subject) async {
    callCount++;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    // 占位线稿：纯白 PNG（仅纯 Mock 模式可达；真链路配置后由
    // FallbackAiService 保证失败透传，不会把白图交给孩子）
    final white = Uint8List.fromList(_tinyWhitePng);
    return [white, white];
  }

  @override
  Future<({String wish, String videoPrompt})> interpretWish(String text,
      {String? subject}) async {
    callCount++;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return (
      wish: 'dance',
      videoPrompt: 'A cute doodle character dancing happily, vibrant colors, '
          'playful children animation style, smooth motion',
    );
  }

  @override
  Future<Uri> animateDrawing({
    required Uint8List imageBytes,
    required String videoPrompt,
    bool Function()? isCancelled,
  }) async {
    callCount++;
    // Mock：2.5 秒"施法"后降级本地动画（GIF 式数据 URI 由 UI 兜底）
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    if (isCancelled?.call() ?? false) throw AnimationCancelled();
    throw MockVideoDegraded();
  }

  @override
  Future<Uint8List?> downloadVideoOrNull(Uri url) async => null;

  @override
  Future<ArtworkAnalysis?> analyzeArtwork(Uint8List pngBytes) async {
    callCount++;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return ArtworkAnalysis(
      subject: '小精灵',
      actions: ArtworkAnalysis.defaultActions,
    );
  }
}

// 1x1 白色 PNG 的字节数据（占位用）
final List<int> _tinyWhitePng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02,
  0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44,
  0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00, 0x00, 0x03, 0x00,
  0x01, 0x5D, 0xDE, 0x7C, 0x89, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
];
