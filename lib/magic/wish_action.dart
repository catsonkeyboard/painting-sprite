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

  /// 内置线稿的预制动作集：主体已知（孩子从线稿库选的），
  /// 不必再调 LLM 看图——零延迟零成本，进屏即显示。
  /// key 与 LineArtLibrary 的 label 一致。
  static const Map<String, ArtworkAnalysis> presets = {
    '恐龙': ArtworkAnalysis(subject: '恐龙', actions: [
      WishAction(label: '奔跑', emoji: '🏃', anim: WishType.run, prompt: 'A cute cartoon dinosaur running happily across a prehistoric meadow, vibrant colors, playful children animation style'),
      WishAction(label: '跳舞', emoji: '🕺', anim: WishType.dance, prompt: 'A cute cartoon dinosaur dancing and wiggling its tail joyfully, vibrant colors, playful children animation style'),
      WishAction(label: '吼叫', emoji: '📢', anim: WishType.sing, prompt: 'A cute cartoon dinosaur roaring happily with sound waves, mouth open wide, playful children animation style'),
      WishAction(label: '跳跃', emoji: '⬆️', anim: WishType.fly, prompt: 'A cute cartoon dinosaur jumping high into the sky, joyful motion, vibrant colors, playful children animation style'),
    ]),
    '小猫': ArtworkAnalysis(subject: '小猫', actions: [
      WishAction(label: '奔跑', emoji: '🏃', anim: WishType.run, prompt: 'A cute cartoon kitten running happily chasing a butterfly, vibrant colors, playful children animation style'),
      WishAction(label: '打滚', emoji: '🤸', anim: WishType.dance, prompt: 'A cute cartoon kitten rolling over playfully on soft grass, joyful motion, vibrant colors, children animation style'),
      WishAction(label: '喵喵叫', emoji: '🎵', anim: WishType.sing, prompt: 'A cute cartoon kitten meowing happily with music notes floating around, playful children animation style'),
      WishAction(label: '跳跃', emoji: '⬆️', anim: WishType.fly, prompt: 'A cute cartoon kitten leaping high to catch a ball of yarn, joyful motion, vibrant colors, children animation style'),
    ]),
    '兔子': ArtworkAnalysis(subject: '兔子', actions: [
      WishAction(label: '蹦蹦跳', emoji: '⬆️', anim: WishType.fly, prompt: 'A cute cartoon bunny hopping and bouncing across a green meadow, ears flopping, playful children animation style'),
      WishAction(label: '奔跑', emoji: '🏃', anim: WishType.run, prompt: 'A cute cartoon bunny sprinting happily with ears streaming behind, vibrant colors, playful children animation style'),
      WishAction(label: '跳舞', emoji: '🕺', anim: WishType.dance, prompt: 'A cute cartoon bunny dancing and twirling joyfully, ears swinging, vibrant colors, children animation style'),
      WishAction(label: '唱歌', emoji: '🎵', anim: WishType.sing, prompt: 'A cute cartoon bunny singing sweetly with music notes around, playful children animation style'),
    ]),
    '独角兽': ArtworkAnalysis(subject: '独角兽', actions: [
      WishAction(label: '飞翔', emoji: '🕊️', anim: WishType.fly, prompt: 'A cute cartoon unicorn flying across a rainbow sky with a sparkling trail, magical colors, children animation style'),
      WishAction(label: '奔跑', emoji: '🏃', anim: WishType.run, prompt: 'A cute cartoon unicorn galloping happily through a flower field, mane flowing, vibrant colors, children animation style'),
      WishAction(label: '闪光', emoji: '✨', anim: WishType.dance, prompt: 'A cute cartoon unicorn twinkling with magical sparkles from its horn, gentle swaying, dreamy colors, children style'),
      WishAction(label: '唱歌', emoji: '🎵', anim: WishType.sing, prompt: 'A cute cartoon unicorn singing with musical sparkles around its horn, joyful, children animation style'),
    ]),
    '火箭': ArtworkAnalysis(subject: '火箭', actions: [
      WishAction(label: '升空', emoji: '🚀', anim: WishType.fly, prompt: 'A cute cartoon rocket blasting off into the starry sky with bright flames and smoke, exciting upward motion, children animation style'),
      WishAction(label: '喷射', emoji: '💨', anim: WishType.fly, prompt: 'A cute cartoon rocket zooming fast with fiery engine trails, dynamic speed lines, vibrant colors, children style'),
      WishAction(label: '旋转', emoji: '🌀', anim: WishType.dance, prompt: 'A cute cartoon rocket spinning and twirling playfully in space with stars around, joyful motion, children style'),
      WishAction(label: '遨游', emoji: '🌟', anim: WishType.run, prompt: 'A cute cartoon rocket cruising peacefully past planets and stars in deep space, dreamy colors, children animation style'),
    ]),
    '金鱼': ArtworkAnalysis(subject: '金鱼', actions: [
      WishAction(label: '游泳', emoji: '🏊', anim: WishType.fly, prompt: 'A cute cartoon goldfish swimming gracefully through sparkling underwater bubbles, flowing fins, children animation style'),
      WishAction(label: '吐泡泡', emoji: '🫧', anim: WishType.sing, prompt: 'A cute cartoon goldfish blowing round shiny bubbles that float upward, playful underwater scene, children style'),
      WishAction(label: '摇摆', emoji: '🐟', anim: WishType.dance, prompt: 'A cute cartoon goldfish swaying and wiggling its tail happily in the water, vibrant colors, children animation style'),
      WishAction(label: '冲刺', emoji: '💨', anim: WishType.run, prompt: 'A cute cartoon goldfish darting quickly through the water with bubble trail, dynamic motion, children style'),
    ]),
    '蝴蝶': ArtworkAnalysis(subject: '蝴蝶', actions: [
      WishAction(label: '飞舞', emoji: '🦋', anim: WishType.fly, prompt: 'A cute cartoon butterfly fluttering among colorful flowers, wings shimmering, gentle breeze, children animation style'),
      WishAction(label: '旋转', emoji: '🌀', anim: WishType.dance, prompt: 'A cute cartoon butterfly twirling and spiraling gracefully in the air, petals swirling around, children style'),
      WishAction(label: '跳舞', emoji: '🕺', anim: WishType.dance, prompt: 'A cute cartoon butterfly dancing happily from flower to flower, wings flapping in rhythm, children style'),
      WishAction(label: '闻花香', emoji: '🌸', anim: WishType.sing, prompt: 'A cute cartoon butterfly resting gently on a blooming flower, enjoying the sweet fragrance, children style'),
    ]),
    '房子': ArtworkAnalysis(subject: '房子', actions: [
      WishAction(label: '长高', emoji: '⬆️', anim: WishType.fly, prompt: 'A cute cartoon house magically growing taller story by story, windows popping out, playful children animation style'),
      WishAction(label: '亮灯', emoji: '💡', anim: WishType.sing, prompt: 'A cute cartoon house lighting up all its warm windows one by one at dusk, cozy glow, children animation style'),
      WishAction(label: '摇晃', emoji: '🌀', anim: WishType.dance, prompt: 'A cute cartoon house wobbling and wiggling playfully like jelly, chimney puffing smoke rings, children style'),
      WishAction(label: '飞起来', emoji: '🕊️', anim: WishType.fly, prompt: 'A cute cartoon house floating up into the sky with colorful balloons attached, dreamy adventure, children style'),
    ]),
  };

  /// 按主体名取预制动作集（内置线稿直用）；未预制返回 null。
  static ArtworkAnalysis? presetFor(String subject) => presets[subject];
}
