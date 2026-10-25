import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:painting_sprite/magic/magic_show.dart';
import 'package:painting_sprite/magic/wish_action.dart';
import 'package:painting_sprite/services/ai_service.dart';

void main() {
  test('默认动作集恰好 4 个，字段齐全且不与麦克风 emoji 冲突', () {
    final d = ArtworkAnalysis.defaultActions;
    expect(d.length, 4);
    for (final a in d) {
      expect(a.label, isNotEmpty);
      expect(a.emoji, isNotEmpty);
      expect(a.emoji.contains('🎤'), isFalse);
      expect(a.prompt, isNotEmpty);
      expect(WishType.values, contains(a.anim));
    }
  });

  test('默认动作集标签与原四愿望一致（向后兼容现有 UI）', () {
    final labels = ArtworkAnalysis.defaultActions.map((a) => a.label).toList();
    expect(labels, ['跳舞', '飞起来', '唱歌', '奔跑']);
  });

  group('MockAiService.analyzeArtwork', () {
    test('返回通用默认动作集（离线可玩）', () async {
      final mock = MockAiService();
      final a = await mock.analyzeArtwork(Uint8List.fromList([1]));
      expect(a, isNotNull);
      expect(a!.subject, '小精灵');
      expect(a.actions.length, 4);
      expect(mock.callCount, 1);
    });
  });
}
