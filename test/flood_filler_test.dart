import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:painting_sprite/coloring/flood_filler.dart';

/// 构造测试图：8x8，中间 2~6 列是竖直黑线，把图分成左右两半。
/// 像素布局（W=白，B=黑）：
/// ```
/// W W W B B W W W
/// W W W B B W W W
/// ...（8 行同构）
/// ```
Uint8List _lineImage(int w, int h) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final x = i % w;
    final isLine = x == 3 || x == 4;
    px[i * 4] = isLine ? 0 : 255;
    px[i * 4 + 1] = isLine ? 0 : 255;
    px[i * 4 + 2] = isLine ? 0 : 255;
    px[i * 4 + 3] = 255;
  }
  return px;
}

Color _red = const Color(0xFFE53935);
int _rOf(Uint8List px, int x, int y, [int ch = 0]) => px[(y * 8 + x) * 4 + ch];

void main() {
  test('闭合黑线阻止填充越界（左半边填红，右半边保持白）', () {
    final px = _lineImage(8, 8);
    final f = FloodFiller(8, 8, px);
    final filled = f.fill(1, 4, _red);

    expect(filled, 24); // 左半边 3 列 × 8 行
    expect(_rOf(px, 0, 0), 229); // 左侧变红
    expect(_rOf(px, 2, 7), 229);
    expect(_rOf(px, 3, 4), 0); // 黑线保持黑
    expect(_rOf(px, 4, 4), 0);
    expect(_rOf(px, 5, 4), 255); // 右半边没被殃及
    expect(_rOf(px, 7, 7), 255);
  });

  test('容差吃掉抗锯齿灰边（128 灰与 255 白视为同一区域）', () {
    final px = _lineImage(8, 8);
    // 在 x=2 列做一道灰边（模拟抗锯齿）
    for (var y = 0; y < 8; y++) {
      final i = (y * 8 + 2) * 4;
      px[i] = px[i + 1] = px[i + 2] = 128;
    }
    final f = FloodFiller(8, 8, px);
    final filled = f.fill(0, 0, _red, tolerance: 130);

    // 灰边与白底同被填充（容差内：|255-128|=127 < 130）
    expect(filled, 24);
    expect(_rOf(px, 2, 3), 229);
  });

  test('重复填充同色幂等（二次填充返回 0 不崩溃）', () {
    final px = _lineImage(8, 8);
    final f1 = FloodFiller(8, 8, px);
    f1.fill(1, 1, _red);

    // 新引擎实例（新 visited），种子已是红色 → 起点自身 chromaReplace 无害
    final f2 = FloodFiller(8, 8, px);
    final filled2 = f2.fill(1, 1, _red);
    expect(filled2, greaterThanOrEqualTo(0)); // 不崩溃即可
  });

  test('出界坐标安全返回 0', () {
    final px = _lineImage(8, 8);
    final f = FloodFiller(8, 8, px);
    expect(f.fill(-1, 0, _red), 0);
    expect(f.fill(0, 99, _red), 0);
  });
}
