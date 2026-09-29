import 'package:flutter/material.dart';

import 'package:painting_sprite/models/stroke.dart';

/// 把 [strokes] 画到白纸上的 CustomPainter。
class DoodlePainter extends CustomPainter {
  DoodlePainter(this.strokes, {this.background = const Color(0xFFFFFFFF)});

  final List<Stroke> strokes;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    for (final s in strokes) {
      final color = s.eraser ? background : s.color;
      if (s.points.length == 1) {
        // 单点：画一个圆点（孩子戳一下也要有反馈）
        canvas.drawCircle(s.points.first, s.width / 2, Paint()..color = color);
        continue;
      }
      final paint = Paint()
        ..color = color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (final p in s.points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(DoodlePainter oldDelegate) => true;
}
