import 'package:flutter_test/flutter_test.dart';

import 'package:painting_sprite/magic/magic_show.dart';
import 'package:painting_sprite/magic/wish_action.dart';

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
}
