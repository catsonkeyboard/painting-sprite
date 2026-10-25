import 'package:flutter/material.dart';

/// 一笔涂鸦：一组轨迹点 + 颜色 + 粗细。
class Stroke {
  Stroke({required this.color, required this.width, this.eraser = false});

  final Color color;
  final double width;
  final bool eraser; // 橡皮 = 用背景色画粗笔
  final List<Offset> points = <Offset>[];

  /// 高刷屏（120-240Hz）下指针事件极密，最小间距抽稀避免点列表无界膨胀。
  void addPoint(Offset p) {
    if (points.isNotEmpty && (p - points.last).distance < 1.0) return;
    points.add(p);
  }

  bool get isEmpty => points.isEmpty;
  int get pointCount => points.length;
}
