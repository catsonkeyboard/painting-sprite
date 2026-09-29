import 'package:flutter/material.dart';

import 'package:painting_sprite/models/stroke.dart';

/// 画板控制器：笔画数据 + 撤销 / 重做 / 清空。
class CanvasController extends ChangeNotifier {
  final List<Stroke> strokes = <Stroke>[];
  final List<Stroke> _redoStack = <Stroke>[];

  Stroke? currentStroke;

  bool get canUndo => strokes.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get isBlank => strokes.isEmpty && currentStroke == null;

  void beginStroke(Offset point, {required Color color, required double width, bool eraser = false}) {
    currentStroke = Stroke(color: color, width: width, eraser: eraser)..addPoint(point);
    notifyListeners();
  }

  void extendStroke(Offset point) {
    currentStroke?.addPoint(point);
    notifyListeners();
  }

  void endStroke() {
    if (currentStroke != null && currentStroke!.pointCount > 0) {
      strokes.add(currentStroke!);
    }
    currentStroke = null;
    notifyListeners();
  }

  void undo() {
    if (strokes.isEmpty) return;
    _redoStack.add(strokes.removeLast());
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    strokes.add(_redoStack.removeLast());
    notifyListeners();
  }

  void clear() {
    strokes.clear();
    _redoStack.clear();
    currentStroke = null;
    notifyListeners();
  }

  /// 所有可见笔画（含正在绘制的一笔），供 Painter 使用。
  List<Stroke> get visibleStrokes =>
      currentStroke == null ? List.unmodifiable(strokes) : [...strokes, currentStroke!];
}
