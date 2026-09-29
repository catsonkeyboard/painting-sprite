import 'package:flutter/material.dart';

/// 画笔配置（颜色 / 粗细 / 橡皮）。
class PenConfig {
  const PenConfig({required this.color, required this.width, this.eraser = false});

  final Color color;
  final double width;
  final bool eraser;
}
