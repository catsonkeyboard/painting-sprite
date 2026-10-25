import 'package:painting_sprite/magic/magic_show.dart';

/// 一个可施法的愿望动作（数据驱动）。
///
/// 由 LLM 看图生成（RealAiService.analyzeArtwork），
/// 或降级时取 [ArtworkAnalysis.defaultActions]。
class WishAction {
  const WishAction({
    required this.label,
    required this.emoji,
    required this.prompt,
    required this.anim,
  });

  final String label; // 中文标签：游泳 / 升空
  final String emoji; // 按钮图标（不得为 🎤，与麦克风冲突）
  final String prompt; // 预生成英文视频提示词（点击直用）
  final WishType anim; // 本地等待动画映射（四选一）
}

/// 画作分析结果：主体 + 4 个推荐动作。
class ArtworkAnalysis {
  const ArtworkAnalysis({required this.subject, required this.actions});

  final String subject;
  final List<WishAction> actions;

  /// 默认动作集：分析失败/未完成时的兜底按钮（= 原固定四愿望）。
  static List<WishAction> get defaultActions => const [
        WishAction(
          label: '跳舞',
          emoji: '🕺',
          prompt: 'A cute doodle character dancing happily, vibrant colors, '
              'playful children animation style',
          anim: WishType.dance,
        ),
        WishAction(
          label: '飞起来',
          emoji: '🕊️',
          prompt: 'A cute doodle character flying in the blue sky with soft '
              'clouds, playful children animation style',
          anim: WishType.fly,
        ),
        WishAction(
          label: '唱歌',
          emoji: '🎵',
          prompt: 'A cute doodle character singing joyfully with colorful '
              'music notes, playful children animation style',
          anim: WishType.sing,
        ),
        WishAction(
          label: '奔跑',
          emoji: '🏃',
          prompt: 'A cute doodle character running happily across a bright '
              'meadow, playful children animation style',
          anim: WishType.run,
        ),
      ];
}
