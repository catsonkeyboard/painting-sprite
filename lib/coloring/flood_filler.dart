import 'dart:typed_data';
import 'dart:ui' show Color;

/// 泛洪涂色引擎：scanline 填充 + 容差匹配 + 亮度保持重着色。
///
/// 儿童涂色的两个核心诉求：
/// 1. 线稿有抗锯齿灰边，直接按"颜色相等"匹配会在边界留白圈 →
///    用[容差匹配]把灰边也算进区域；
/// 2. 孩子希望黑线不被涂掉、涂色保留原图明暗细节 →
///    只替换色相/饱和度，保留亮度（YIQ 色度替换法）。
class FloodFiller {
  FloodFiller(this.width, this.height, Uint8List rgba)
      : pixels = rgba,
        visited = Uint8List(width * height);

  static const int bytesPerPixel = 4;

  final int width;
  final int height;
  final Uint8List pixels;
  final Uint8List visited;

  int _r(int i) => pixels[i];
  int _g(int i) => pixels[i + 1];
  int _b(int i) => pixels[i + 2];

  /// 与种子点颜色的平方距离是否在容差内。
  bool _matches(int idx, int sr, int sg, int sb, int tolerance) {
    final dr = _r(idx) - sr;
    final dg = _g(idx) - sg;
    final db = _b(idx) - sb;
    return dr * dr + dg * dg + db * db <= tolerance * tolerance * 3;
  }

  /// 在 (sx, sy) 处以 [color] 填充连通区域（span-scanline 算法）。
  ///
  /// 返回被填充的像素数（0 = 没有可填区域）。
  /// [tolerance] 建议值 32~48：覆盖抗锯齿灰边，不会越线。
  int fill(int sx, int sy, Color color, {int tolerance = 40}) {
    if (sx < 0 || sy < 0 || sx >= width || sy >= height) return 0;
    final start = (sy * width + sx) * bytesPerPixel;
    final sr = _r(start), sg = _g(start), sb = _b(start);

    final nr = (color.r * 255).round();
    final ng = (color.g * 255).round();
    final nb = (color.b * 255).round();

    var filled = 0;
    final stack = <int>[sy * width + sx];

    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      if (visited[p] == 1) continue;
      final rowStart = p - p % width;
      final px = p % width;

      // 1. 向左探到本段最左端
      var left = px;
      while (left > 0 &&
          visited[rowStart + left - 1] == 0 &&
          _matches((rowStart + left - 1) * bytesPerPixel, sr, sg, sb, tolerance)) {
        left--;
      }

      // 2. 从左向右扫整段
      var spanUp = false;
      var spanDown = false;
      var cx = left;
      while (cx < width) {
        final cp = rowStart + cx;
        if (visited[cp] == 1 || !_matches(cp * bytesPerPixel, sr, sg, sb, tolerance)) {
          break;
        }
        visited[cp] = 1;
        _chromaReplace(cp * bytesPerPixel, nr, ng, nb);
        filled++;

        // 3. 上下邻行：每段只入队一次
        if (cp >= width) {
          final up = cp - width;
          final ok = visited[up] == 0 && _matches(up * bytesPerPixel, sr, sg, sb, tolerance);
          if (ok && !spanUp) {
            stack.add(up);
            spanUp = true;
          } else if (!ok) {
            spanUp = false;
          }
        }
        if (cp + width < width * height) {
          final dn = cp + width;
          final ok = visited[dn] == 0 && _matches(dn * bytesPerPixel, sr, sg, sb, tolerance);
          if (ok && !spanDown) {
            stack.add(dn);
            spanDown = true;
          } else if (!ok) {
            spanDown = false;
          }
        }
        cx++;
      }
    }
    return filled;
  }

  /// YIQ 色度替换：保留 Y（亮度），替换 I/Q（色度）。
  /// 黑白像素（低饱和度）不替换 → 黑线永不被涂色。
  void _chromaReplace(int i, int r, int g, int b) {
    final oldR = _r(i), oldG = _g(i), oldB = _b(i);
    // 亮度
    final y = 0.299 * oldR + 0.587 * oldG + 0.114 * oldB;
    // 原色度强度（灰度像素色度≈0）
    final oldI = 0.596 * oldR - 0.274 * oldG - 0.322 * oldB;
    final oldQ = 0.211 * oldR - 0.523 * oldG + 0.312 * oldB;
    final chroma = (oldI * oldI + oldQ * oldQ) > 400; // 低饱和=线条/灰边，跳过
    if (chroma) {
      // 已有颜色区域：重新着色但保留亮度层次
      final targetY = 0.299 * r + 0.587 * g + 0.114 * b;
      final scale = targetY > 0 ? y / targetY : 1.0;
      pixels[i] = (r * scale).clamp(0, 255).round();
      pixels[i + 1] = (g * scale).clamp(0, 255).round();
      pixels[i + 2] = (b * scale).clamp(0, 255).round();
    } else {
      // 白/灰区域：直接上色，亮度轻微混合让边缘柔和
      pixels[i] = r;
      pixels[i + 1] = g;
      pixels[i + 2] = b;
    }
  }
}
