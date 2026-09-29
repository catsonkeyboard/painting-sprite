import 'package:flutter/material.dart';

/// 应用共享 UI 素材：专为 3-6 岁设计的超大触摸目标与糖果色。
class KidUi {
  static const double minTouch = 64; // 学龄前儿童最小触摸目标

  static const List<Color> palette = [
    Color(0xFFE53935), // 红
    Color(0xFFFB8C00), // 橙
    Color(0xFFFDD835), // 黄
    Color(0xFF43A047), // 绿
    Color(0xFF1E88E5), // 蓝
    Color(0xFF8E24AA), // 紫
    Color(0xFFEC407A), // 粉
    Color(0xFF8D6E63), // 棕
    Color(0xFF212121), // 黑
    Color(0xFFFFFFFF), // 白
  ];

  static ThemeData theme() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF)),
        scaffoldBackgroundColor: const Color(0xFFFFF8E7),
      );

  /// 圆滚滚大按钮。
  static Widget bigButton({
    required Widget child,
    required VoidCallback onTap,
    Color? color,
    double size = 72,
  }) {
    return Material(
      color: color ?? const Color(0xFFFFD54F),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: child),
        ),
      ),
    );
  }
}
