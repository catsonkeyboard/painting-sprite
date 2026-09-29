import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:painting_sprite/painting/canvas_controller.dart';
import 'package:painting_sprite/painting/doodle_canvas.dart';
import 'package:painting_sprite/painting/pen_config.dart';
import 'package:painting_sprite/services/speech_service.dart';
import 'package:painting_sprite/ui/kid_ui.dart';

/// 屏 ①：自由涂鸦 —— 大画笔大色盘，圆肌肉友好。
class DrawScreen extends StatefulWidget {
  const DrawScreen({super.key, required this.speech, required this.onDone});

  final SpeechService speech;

  /// 作品 PNG 字节交给魔法屏。
  final void Function(Uint8List png) onDone;

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen> {
  final _controller = CanvasController();
  final _pen = ValueNotifier<PenConfig>(
    const PenConfig(color: Color(0xFF212121), width: 10),
  );
  final _canvasKey = GlobalKey<DoodleCanvasState>();

  double _brush = 10;

  @override
  void initState() {
    super.initState();
    widget.speech.speak(MagicPhrases.goDraw); // 进入引导
  }

  void _setBrush(double w) {
    _brush = w;
    final p = _pen.value;
    _pen.value = PenConfig(color: p.color, width: w, eraser: p.eraser);
  }

  void _setColor(Color c) {
    _pen.value = PenConfig(color: c, width: _brush, eraser: false);
  }

  void _toggleEraser() {
    final p = _pen.value;
    _pen.value = PenConfig(color: p.color, width: 28, eraser: !p.eraser);
  }

  Future<void> _finish() async {
    if (_controller.isBlank) return;
    final png = await _canvasKey.currentState!.exportPngBytes();
    await widget.speech.speak(MagicPhrases.toMagic);
    widget.onDone(png);
  }

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
                child: DoodleCanvas(
                  key: _canvasKey,
                  controller: _controller,
                  pen: _pen,
                ),
              ),
            ),
          ),
          _buildToolbar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 色盘
            SizedBox(
              height: KidUi.minTouch,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final c in KidUi.palette)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: GestureDetector(
                        onTap: () => _setColor(c),
                        child: Container(
                          width: KidUi.minTouch - 12,
                          height: KidUi.minTouch - 12,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _pen.value.color == c && !_pen.value.eraser
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
            const SizedBox(height: 8),
            // 笔刷粗细（小/中/大）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final w in const [6.0, 12.0, 22.0])
                  KidUi.bigButton(
                    size: KidUi.minTouch,
                    color: _brush == w ? const Color(0xFFFFB74D) : Colors.white,
                    onTap: () => _setBrush(w),
                    child: Container(
                      width: w + 6,
                      height: w + 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF212121),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                // 橡皮
                KidUi.bigButton(
                  size: KidUi.minTouch,
                  color: _pen.value.eraser ? const Color(0xFFFFB74D) : Colors.white,
                  onTap: _toggleEraser,
                  child: const Icon(Icons.cleaning_services, size: 32, color: Color(0xFF212121)),
                ),
                // 撤销
                KidUi.bigButton(
                  size: KidUi.minTouch,
                  color: Colors.white,
                  onTap: _controller.undo,
                  child: const Icon(Icons.undo, size: 32, color: Color(0xFF212121)),
                ),
                // 清空
                KidUi.bigButton(
                  size: KidUi.minTouch,
                  color: Colors.white,
                  onTap: () => _controller.clear(),
                  child: const Icon(Icons.delete_outline, size: 32, color: Color(0xFF212121)),
                ),
                // 完成 → 施魔法
                KidUi.bigButton(
                  size: KidUi.minTouch,
                  color: const Color(0xFF7C4DFF),
                  onTap: _finish,
                  child: const Icon(Icons.auto_awesome, size: 34, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
