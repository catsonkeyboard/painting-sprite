import 'package:flutter_test/flutter_test.dart';

import 'package:painting_sprite/painting/canvas_controller.dart';
import 'package:painting_sprite/services/speech_service.dart';
import 'package:flutter/material.dart';

void main() {
  group('CanvasController', () {
    test('画一笔：begin/extend/end 全流程', () {
      final c = CanvasController();
      c.beginStroke(const Offset(0, 0), color: Colors.red, width: 8);
      c.extendStroke(const Offset(10, 10));
      c.extendStroke(const Offset(20, 20));
      expect(c.currentStroke, isNotNull);
      expect(c.currentStroke!.pointCount, 3);
      c.endStroke();
      expect(c.strokes.length, 1);
      expect(c.currentStroke, isNull);
      expect(c.visibleStrokes.length, 1);
    });

    test('撤销 / 重做 / 清空', () {
      final c = CanvasController();
      c.beginStroke(const Offset(0, 0), color: Colors.red, width: 8);
      c.endStroke();
      c.beginStroke(const Offset(5, 5), color: Colors.blue, width: 8);
      c.endStroke();
      expect(c.strokes.length, 2);

      c.undo();
      expect(c.strokes.length, 1);
      expect(c.canRedo, isTrue);

      c.redo();
      expect(c.strokes.length, 2);

      c.clear();
      expect(c.isBlank, isTrue);
      expect(c.canUndo, isFalse);
      expect(c.canRedo, isFalse);
    });

    test('橡皮笔画标记 eraser', () {
      final c = CanvasController();
      c.beginStroke(const Offset(1, 1), color: Colors.white, width: 28, eraser: true);
      c.endStroke();
      expect(c.strokes.first.eraser, isTrue);
    });
  });

  group('MagicPhrases', () {
    test('话术非空（零文字 UI 的声音界面）', () {
      expect(MagicPhrases.welcome, isNotEmpty);
      expect(MagicPhrases.casting, isNotEmpty);
      expect(MagicPhrases.done, isNotEmpty);
      expect(MagicPhrases.fallback, isNotEmpty);
    });
  });

  group('FakeSpeechService', () {
    test('记录播报内容', () async {
      final s = FakeSpeechService();
      await s.speak('你好');
      await s.speak('魔法');
      expect(s.spoken, ['你好', '魔法']);
    });
  });
}
