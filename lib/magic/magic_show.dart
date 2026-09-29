import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 愿望类型（与 4 个预设大按钮对应，也用于语音分类）。
enum WishType {
  dance('跳舞', '🕺'),
  fly('飞起来', '🕊️'),
  sing('唱歌', '🎤'),
  run('奔跑', '🏃');

  const WishType(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// 本地魔法动画引擎：让精灵图在等待云端视频期间"活起来"，
/// 也是云端失败/断网时的兜底演出。零成本、<1 秒出效果。
class MagicShow extends StatefulWidget {
  const MagicShow({
    super.key,
    required this.child,
    this.wish = WishType.dance,
    this.autoPlay = true,
  });

  final Widget child; // 精灵图（涂鸦 PNG / 线稿）
  final WishType wish;
  final bool autoPlay;

  @override
  State<MagicShow> createState() => _MagicShowState();
}

class _MagicShowState extends State<MagicShow> with TickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.autoPlay) _controller.repeat();
  }

  @override
  void didUpdateWidget(MagicShow old) {
    super.didUpdateWidget(old);
    if (old.wish != widget.wish) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final transform = switch (widget.wish) {
          WishType.dance => _dance(t), // 果冻摇摆扭一扭
          WishType.fly => _fly(t), // 起伏飘动
          WishType.sing => _sing(t), // 点头哼唱
          WishType.run => _run(t), // 前倾颠簸
        };
        return Transform(
          alignment: Alignment.center,
          transform: transform,
          child: widget.child,
        );
      },
    );
  }

  // 正弦辅助：t ∈ [0,1)
  double _sin(double t, {double freq = 1, double phase = 0, double min = -1, double max = 1}) {
    final v = math.sin((t * freq + phase) * 2 * math.pi);
    return min + (v + 1) / 2 * (max - min);
  }

  Matrix4 _dance(double t) => Matrix4.identity()
    ..rotateZ(_sin(t, min: -0.12, max: 0.12))
    ..scaleByDouble(1.0 + 0.05 * math.sin(t * 2 * math.pi), 1.0 - 0.05 * math.sin(t * 2 * math.pi), 1, 1);

  Matrix4 _fly(double t) => Matrix4.identity()
    ..translateByDouble(0.0, -20 * math.sin(t * 2 * math.pi) - 10, 0, 1)
    ..rotateZ(_sin(t, freq: 2, min: -0.06, max: 0.06));

  Matrix4 _sing(double t) => Matrix4.identity()
    ..rotateZ(_sin(t, freq: 2, min: -0.04, max: 0.04))
    ..translateByDouble(0.0, -6 * math.sin(t * 4 * math.pi), 0, 1);

  Matrix4 _run(double t) => Matrix4.identity()
    ..rotateZ(0.08)
    ..translateByDouble(0.0, -8 * (0.5 - 0.5 * math.cos(t * 4 * math.pi)), 0, 1);
}

/// 魔法粒子背景：等待期营造"施法中"氛围。
class MagicParticles extends StatefulWidget {
  const MagicParticles({super.key, this.count = 24});

  final int count;

  @override
  State<MagicParticles> createState() => _MagicParticlesState();
}

class _MagicParticlesState extends State<MagicParticles> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  late final List<_Particle> _particles = List.generate(
    widget.count,
    (i) => _Particle.random(i),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => CustomPaint(
          painter: _ParticlePainter(_particles, _ctrl.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Particle {
  _Particle(this.x, this.hue, this.size, this.speed, this.phase);

  factory _Particle.random(int seed) {
    final r = math.Random(seed);
    return _Particle(
      r.nextDouble(), // 水平位置 0..1
      r.nextDouble() * 360, // 色相
      2 + r.nextDouble() * 4, // 尺寸
      0.15 + r.nextDouble() * 0.3, // 上飘速度（周期倍率）
      r.nextDouble(), // 相位
    );
  }

  final double x;
  final double hue;
  final double size;
  final double speed;
  final double phase;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.particles, this.t);

  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      // y 从底部往上飘，取模循环
      final progress = (t * p.speed + p.phase) % 1.0;
      final y = size.height * (1 - progress);
      final x = size.width * (p.x + 0.05 * math.sin((t + p.phase) * 2 * math.pi));
      final opacity = math.sin(progress * math.pi); // 淡入淡出
      paint.color = HSLColor.fromAHSL(opacity * 0.85, p.hue, 0.8, 0.65).toColor();
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) => true;
}
