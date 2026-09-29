import 'dart:typed_data';

/// AI 服务抽象：W2/W3 的所有云端能力挂在下面，实现可插拔
/// （Mock 用于开发测试；正式实现读 ai_keys.json 直连厂商 API）。
///
/// 密钥纪律：ai_keys.json 已 gitignore，绝不提交仓库。
abstract class AiService {
  /// 语音识别：音频 → 文本（孩子说"我要小恐龙"）。
  Future<String> transcribe(Uint8List audioBytes);

  /// 线稿生成：文本 → 线稿 PNG（生成 2 张供孩子二选一）。
  Future<List<Uint8List>> generateLineArt(String subject);

  /// 愿望理解：文本 → (愿望类型, 英文视频提示词)。
  Future<({String wish, String videoPrompt})> interpretWish(String text);

  /// 图生视频：作品图 + 提示词 → 动画视频 URL（UI 层播放）。
  Future<Uri> animateDrawing({
    required Uint8List imageBytes,
    required String videoPrompt,
  });
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
    // 占位线稿：纯白 PNG（W2 后续替换为内置线稿库匹配/真实 API）
    final white = Uint8List.fromList(_tinyWhitePng);
    return [white, white];
  }

  @override
  Future<({String wish, String videoPrompt})> interpretWish(String text) async {
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
  }) async {
    callCount++;
    // Mock：2.5 秒"施法"后返回动态占位（GIF 式数据 URI 由 UI 兜底本地动画）
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    throw UnimplementedError('__mock_video_degraded__');
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
