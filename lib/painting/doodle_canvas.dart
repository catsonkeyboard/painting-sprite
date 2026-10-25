import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:painting_sprite/painting/canvas_controller.dart';
import 'package:painting_sprite/painting/doodle_painter.dart';
import 'package:painting_sprite/painting/pen_config.dart';

/// 手绘画布：指针捕获 + 绘制 + PNG 导出。
///
/// 通过 `GlobalKey<DoodleCanvasState>` 拿到 state 后可调用
/// [exportImage] / [exportPngBytes] 导出作品。
///
/// 用 [Listener] 而非 GestureDetector：pan 手势要过 kTouchSlop（≈18px）
/// 才触发，孩子轻点会完全没有笔迹、起笔也会被吞掉一段。
class DoodleCanvas extends StatefulWidget {
  const DoodleCanvas({super.key, required this.controller, required this.pen});

  final CanvasController controller;
  final ValueListenable<PenConfig> pen;

  @override
  State<DoodleCanvas> createState() => DoodleCanvasState();
}

class DoodleCanvasState extends State<DoodleCanvas> {
  final GlobalKey _boundaryKey = GlobalKey();
  int? _activePointer; // 多点触控：只跟踪第一根手指（简易手掌误触抑制）

  /// 导出为高分辨率图像（送去施魔法 / 存相册用）。
  /// 分辨率至少 2x，设备 DPR 更高时跟随设备。
  Future<ui.Image> exportImage() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      throw StateError('DoodleCanvas 尚未完成布局，无法导出');
    }
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    return boundary.toImage(pixelRatio: dpr < 2 ? 2 : dpr);
  }

  Future<Uint8List> exportPngBytes() async {
    final image = await exportImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('PNG 编码失败');
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: ClipRect(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (_activePointer != null) return;
            _activePointer = e.pointer;
            final p = widget.pen.value;
            widget.controller.beginStroke(
              e.localPosition,
              color: p.color,
              width: p.width,
              eraser: p.eraser,
            );
          },
          onPointerMove: (e) {
            if (e.pointer != _activePointer) return;
            widget.controller.extendStroke(e.localPosition);
          },
          onPointerUp: (e) {
            if (e.pointer != _activePointer) return;
            _activePointer = null;
            widget.controller.endStroke();
          },
          onPointerCancel: (e) {
            if (e.pointer != _activePointer) return;
            _activePointer = null;
            widget.controller.endStroke();
          },
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => CustomPaint(
              painter: DoodlePainter(widget.controller.visibleStrokes),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}
