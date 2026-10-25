import 'package:flutter/material.dart';

/// 应用共享 UI 素材：专为 3-6 岁设计的超大触摸目标与糖果色。
class KidUi {
  static const double minTouch = 64; // 学龄前儿童最小触摸目标

  // ---- 全局色彩常量（改主题只动这里）----
  static const Color canvasBackground = Color(0xFFFFFFFF); // 画布/橡皮底色
  static const Color bgCream = Color(0xFFFFF8E7); // 米黄页面底
  static const Color textBrown = Color(0xFF5D4037); // 主文字棕
  static const Color textBrownLight = Color(0xFF8D6E63); // 次文字棕
  static const Color inkDark = Color(0xFF212121); // 画笔黑/图标深色
  static const Color magicPurple = Color(0xFF7C4DFF); // 魔法紫（选中/强调）
  static const Color accentOrange = Color(0xFFFFB74D); // 选中高亮橙
  static const Color cardYellow = Color(0xFFFFE082); // 卡片描边黄
  static const Color micBlue = Color(0xFF81D4FA); // 麦克风蓝
  static const Color micRecording = Color(0xFFFF7043); // 录音中橙红

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
        colorScheme: ColorScheme.fromSeed(seedColor: magicPurple),
        scaffoldBackgroundColor: bgCream,
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

/// 左上角返回大按钮：桌面端（Windows/macOS）没有系统返回键，
/// 无 AppBar 的全屏页面必须自带可见出口。
///
/// 默认走 [Navigator.maybePop]：PopScope 拦截逻辑（画画屏挽留 /
/// 魔法屏施法中劝等）会照常生效。
class KidBackButton extends StatelessWidget {
  const KidBackButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 8,
      child: KidUi.bigButton(
        size: KidUi.minTouch,
        color: Colors.white,
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        child: const Text('⬅️', style: TextStyle(fontSize: 28)),
      ),
    );
  }
}
