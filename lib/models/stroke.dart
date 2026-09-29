import 'package:flutter/material.dart';

/// 一笔涂鸦：一组轨迹点 + 颜色 + 粗细。
class Stroke {
  Stroke({required this.color, required this.width, this.eraser = false});

  final Color color;
  final double width;
  final bool eraser; // 橡皮 = 用背景色画粗笔
  final List<Offset> points = <Offset>[];

  void addPoint(Offset p) => points.add(p);

  bool get isEmpty => points.isEmpty;
  int get pointCount => points.length;
}
