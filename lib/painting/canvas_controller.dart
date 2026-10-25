import 'package:flutter/material.dart';

import 'package:painting_sprite/models/stroke.dart';

/// 画板控制器：笔画数据 + 撤销 / 重做 / 清空。
class CanvasController extends ChangeNotifier {
  /// 撤销历史上限（防长时间涂鸦内存无界）。
  static const int maxStrokes = 200;

  final List<Stroke> strokes = <Stroke>[];
  final List<Stroke> _redoStack = <Stroke>[];

  Stroke? currentStroke;

  bool get canUndo => strokes.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get isBlank => strokes.isEmpty && currentStroke == null;

  void beginStroke(Offset point, {required Color color, required double width, bool eraser = false}) {
    // 新笔画一旦落笔，重做历史即作废（否则撤销掉的笔画会复活在新笔画之上）
    _redoStack.clear();
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
      if (strokes.length > maxStrokes) strokes.removeAt(0);
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
