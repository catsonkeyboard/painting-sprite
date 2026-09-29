import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 作品条目：原图 + 愿望 + 动画（本地相册，无云）。
class Artwork {
  Artwork({
    required this.id,
    required this.pngPath,
    required this.wish,
    this.videoPath,
    required this.createdAt,
  });

  final String id; // 时间戳 id
  final String pngPath;
  final String wish; // 愿望文本（中文）
  final String? videoPath; // 本地 mp4 或云端 URL（可空 = 本地动画作品）
  final DateTime createdAt;

  bool get hasVideo => videoPath != null;
}

/// 本地相册：图片/视频直存 + wishes.json 索引。
class ArtworkStore {
  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/artworks');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static final Map<String, Artwork> _index = {};
  static bool _loaded = false;

  /// 保存作品，返回条目。videoBytes 优先；否则 videoUrl 记入索引在线播。
  static Future<Artwork> save({
    required List<int> pngBytes,
    required String wish,
    List<int>? videoBytes,
    String? videoUrl,
  }) async {
    final dir = await _dir();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final png = File('${dir.path}/$id.png');
    await png.writeAsBytes(pngBytes);

    String? videoPath;
    if (videoBytes != null) {
      final mp4 = File('${dir.path}/$id.mp4');
      await mp4.writeAsBytes(videoBytes);
      videoPath = mp4.path;
    } else if (videoUrl != null) {
      videoPath = videoUrl;
    }

    final art = Artwork(
      id: id,
      pngPath: png.path,
      wish: wish,
      videoPath: videoPath,
      createdAt: DateTime.now(),
    );
    _index[id] = art;
    await _flush();
    return art;
  }

  /// 启动重建索引：png 文件系统扫描 + wishes.json 合并。
  static Future<List<Artwork>> list() async {
    if (!_loaded) {
      _loaded = true;
      final dir = await _dir();
      final wishes = await _loadWishes();
      final pngs = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'));
      for (final f in pngs) {
        final id = f.path.split('/').last.replaceAll('.png', '');
        final mp4 = File('${dir.path}/$id.mp4');
        _index[id] = Artwork(
          id: id,
          pngPath: f.path,
          wish: wishes[id] ?? '',
          videoPath: await mp4.exists() ? mp4.path : wishes['$id.video'],
          createdAt:
              DateTime.fromMillisecondsSinceEpoch(int.tryParse(id) ?? 0),
        );
      }
    }
    final list = _index.values.toList()..sort((a, b) => b.id.compareTo(a.id));
    return list;
  }

  static Future<void> delete(Artwork art) async {
    _index.remove(art.id);
    await File(art.pngPath).delete().catchError((_) => File(art.pngPath));
    if (art.videoPath != null && !art.videoPath!.startsWith('http')) {
      await File(art.videoPath!)
          .delete()
          .catchError((_) => File(art.videoPath!));
    }
    final wishes = await _loadWishes();
    wishes.remove(art.id);
    wishes.remove('${art.id}.video');
    await _writeWishes(wishes);
  }

  // ---- wishes.json：{id: 愿望文本, "id.video": url} ----

  static Future<Map<String, String>> _loadWishes() async {
    try {
      final f = File('${(await _dir()).path}/wishes.json');
      if (!await f.exists()) return {};
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeWishes(Map<String, String> m) async {
    final f = File('${(await _dir()).path}/wishes.json');
    await f.writeAsString(jsonEncode(m));
  }

  static Future<void> _flush() async {
    final wishes = await _loadWishes();
    for (final a in _index.values) {
      wishes[a.id] = a.wish;
      if (a.videoPath != null && a.videoPath!.startsWith('http')) {
        wishes['${a.id}.video'] = a.videoPath!;
      }
    }
    await _writeWishes(wishes);
  }
}
