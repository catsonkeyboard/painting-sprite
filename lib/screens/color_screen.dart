import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:painting_sprite/painting/canvas_controller.dart';
import 'package:painting_sprite/painting/doodle_canvas.dart';
import 'package:painting_sprite/painting/pen_config.dart';
import 'package:painting_sprite/ui/kid_ui.dart';

/// 屏 ②：涂色屏（W1 骨架版）。
///
/// W1：自由画笔模式占位（线稿图层 W2 接入，见设计文档 §3.3）。
/// 孩子先能在带线稿底图上描画；W2 换成"语音生成线稿 + 泛洪涂色"。
class ColorScreen extends StatefulWidget {
  const ColorScreen({super.key, required this.onDone});

  final void Function(Uint8List png) onDone;

  @override
  State<ColorScreen> createState() => _ColorScreenState();
}

class _ColorScreenState extends State<ColorScreen> {
  final _controller = CanvasController();
  final _pen = ValueNotifier<PenConfig>(
    const PenConfig(color: Color(0xFFE53935), width: 26),
  );
  final _canvasKey = GlobalKey<DoodleCanvasState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    DoodleCanvas(
                      key: _canvasKey,
                      controller: _controller,
                      pen: _pen,
                    ),
                    // W2: 线稿图层（语音生成 / 内置线稿库）插这里
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: _ComingSoonBadge(label: '🎨 语音线稿 W2 上线'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildPalette(),
        ],
      ),
    );
  }

  Widget _buildPalette() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SizedBox(
          height: KidUi.minTouch,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final c in KidUi.palette)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GestureDetector(
                    onTap: () => _pen.value = PenConfig(color: c, width: 26),
                    child: Container(
                      width: KidUi.minTouch - 12,
                      height: KidUi.minTouch - 12,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _pen.value.color == c
                              ? const Color(0xFF7C4DFF)
                              : Colors.grey.shade300,
                          width: 4,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComingSoonBadge extends StatelessWidget {
  const _ComingSoonBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037)),
      ),
    );
  }
}
