import 'dart:async';
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
    const PenConfig(color: KidUi.inkDark, width: 10),
  );
  final _canvasKey = GlobalKey<DoodleCanvasState>();

  double _brush = 10;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    widget.speech.speak(MagicPhrases.goDraw); // 进入引导
  }

  @override
  void dispose() {
    _controller.dispose();
    _pen.dispose();
    super.dispose();
  }

  void _setBrush(double w) {
    setState(() {
      _brush = w;
      final p = _pen.value;
      _pen.value = PenConfig(color: p.color, width: w, eraser: p.eraser);
    });
  }

  void _setColor(Color c) {
    setState(() {
      _pen.value = PenConfig(color: c, width: _brush, eraser: false);
    });
  }

  void _toggleEraser() {
    setState(() {
      final p = _pen.value;
      final eraserOn = !p.eraser;
      // 退出橡皮时恢复笔宽，避免"看似中档笔画出 28 粗的线"
      _pen.value = PenConfig(
        color: p.color,
        width: eraserOn ? 28.0 : _brush,
        eraser: eraserOn,
      );
    });
  }

  Future<void> _finish() async {
    if (_exporting) return;
    if (_controller.isBlank) {
      unawaited(widget.speech.speak(MagicPhrases.drawFirst));
      return;
    }
    _exporting = true;
    try {
      final state = _canvasKey.currentState;
      if (state == null) throw StateError('画布未挂载');
      final png = await state.exportPngBytes();
      await widget.speech.speak(MagicPhrases.toMagic);
      widget.onDone(png);
    } catch (e) {
      debugPrint('画作导出失败：$e');
      unawaited(widget.speech.speak(MagicPhrases.tryAgain));
    } finally {
      _exporting = false;
    }
  }

  /// 有笔画时拦返回键：孩子误触不丢作品。
  Future<void> _onPopInvoked(bool didPop) async {
    if (didPop) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: KidUi.bgCream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🖌️ 画还没施魔法呢！', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: KidUi.textBrown)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  KidUi.bigButton(
                    size: KidUi.minTouch,
                    color: Colors.white,
                    onTap: () => Navigator.of(ctx).pop(false),
                    child: const Text('✏️', style: TextStyle(fontSize: 30)),
                  ),
                  KidUi.bigButton(
                    size: KidUi.minTouch,
                    color: const Color(0xFFFFAB91),
                    onTap: () => Navigator.of(ctx).pop(true),
                    child: const Text('👋', style: TextStyle(fontSize: 30)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _controller.isBlank,
      onPopInvokedWithResult: (didPop, _) => _onPopInvoked(didPop),
      child: Scaffold(
        body: Stack(
          children: [
            Column(
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
            const KidBackButton(), // 桌面端没有系统返回键
          ],
        ),
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
            // 色盘（横向滚动；64pt 命中热区，圆点视觉略小）
            SizedBox(
              height: KidUi.minTouch,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final c in KidUi.palette)
                    GestureDetector(
                      onTap: () => _setColor(c),
                      child: SizedBox(
                        width: KidUi.minTouch,
                        height: KidUi.minTouch,
                        child: Center(
                          child: Container(
                            width: KidUi.minTouch - 12,
                            height: KidUi.minTouch - 12,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _pen.value.color == c && !_pen.value.eraser
                                    ? KidUi.magicPurple
                                    : Colors.grey.shade300,
                                width: 4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 工具行：Wrap 自适应，窄屏自动折行（固定 Row 会溢出）
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final w in const [6.0, 12.0, 22.0])
                  KidUi.bigButton(
                    size: KidUi.minTouch,
                    color: _brush == w && !_pen.value.eraser ? KidUi.accentOrange : Colors.white,
                    onTap: () => _setBrush(w),
                    child: Container(
                      width: w + 6,
                      height: w + 6,
                      decoration: const BoxDecoration(
                        color: KidUi.inkDark,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                // 橡皮
                KidUi.bigButton(
                  size: KidUi.minTouch,
                  color: _pen.value.eraser ? KidUi.accentOrange : Colors.white,
                  onTap: _toggleEraser,
                  child: const Icon(Icons.cleaning_services, size: 32, color: KidUi.inkDark),
                ),
                // 撤销 / 重做
                KidUi.bigButton(
                  size: KidUi.minTouch,
                  color: Colors.white,
                  onTap: _controller.undo,
                  child: const Icon(Icons.undo, size: 32, color: KidUi.inkDark),
                ),
                KidUi.bigButton(
                  size: KidUi.minTouch,
                  color: Colors.white,
                  onTap: _controller.redo,
                  child: const Icon(Icons.redo, size: 32, color: KidUi.inkDark),
                ),
                // 清空
                KidUi.bigButton(
                  size: KidUi.minTouch,
                  color: Colors.white,
                  onTap: () => _controller.clear(),
                  child: const Icon(Icons.delete_outline, size: 32, color: KidUi.inkDark),
                ),
                // 完成 → 施魔法
                KidUi.bigButton(
                  size: KidUi.minTouch,
                  color: KidUi.magicPurple,
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
