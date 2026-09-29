import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:painting_sprite/painting/canvas_controller.dart';
import 'package:painting_sprite/painting/doodle_painter.dart';
import 'package:painting_sprite/painting/pen_config.dart';

/// 手绘画布：手势捕获 + 绘制 + PNG 导出。
///
/// 通过 `GlobalKey<DoodleCanvasState>` 拿到 state 后可调用
/// [exportImage] / [exportPngBytes] 导出作品。
class DoodleCanvas extends StatefulWidget {
  const DoodleCanvas({super.key, required this.controller, required this.pen});

  final CanvasController controller;
  final ValueListenable<PenConfig> pen;

  @override
  State<DoodleCanvas> createState() => DoodleCanvasState();
}

class DoodleCanvasState extends State<DoodleCanvas> {
  final GlobalKey _boundaryKey = GlobalKey();

  /// 导出为 2x 分辨率图像（送去施魔法 / 存相册用）。
  Future<ui.Image> exportImage() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      throw StateError('DoodleCanvas 尚未完成布局，无法导出');
    }
    return boundary.toImage(pixelRatio: 2);
  }

  Future<Uint8List> exportPngBytes() async {
    final image = await exportImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('PNG 编码失败');
    }
    return data.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: ClipRect(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            final p = widget.pen.value;
            widget.controller.beginStroke(
              d.localPosition,
              color: p.color,
              width: p.width,
              eraser: p.eraser,
            );
          },
          onPanUpdate: (d) => widget.controller.extendStroke(d.localPosition),
          onPanEnd: (_) => widget.controller.endStroke(),
          onPanCancel: () => widget.controller.endStroke(),
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
