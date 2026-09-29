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
  final String? videoPath; // 云端动画（可空 = 本地动画作品）
  final DateTime createdAt;

  bool get hasVideo => videoPath != null;
}

/// 本地相册：JSON 索引 + 文件直存（家长手动备份目录即可）。
class ArtworkStore {
  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/artworks');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 保存作品，返回条目。
  static Future<Artwork> save({
    required List<int> pngBytes,
    required String wish,
    List<int>? videoBytes,
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

  static final Map<String, Artwork> _index = {};

  static Future<List<Artwork>> list() async {
    if (_index.isEmpty) {
      final dir = await _dir();
      // 启动时从文件系统重建索引（png+同名 mp4 配对）
      final entities = dir.listSync();
      final pngs = entities.whereType<File>().where((f) => f.path.endsWith('.png'));
      for (final f in pngs) {
        final id = f.path.split('/').last.replaceAll('.png', '');
        final mp4 = File('${dir.path}/$id.mp4');
        _index[id] = Artwork(
          id: id,
          pngPath: f.path,
          wish: '',
          videoPath: await mp4.exists() ? mp4.path : null,
          createdAt: File(f.path).lastAccessedSync(),
        );
      }
    }
    final list = _index.values.toList()..sort((a, b) => b.id.compareTo(a.id));
    return list;
  }

  static Future<void> _flush() async {
    // 索引仅内存态 + 文件系统即真相（YAGNI：不落盘 JSON）
  }
}
