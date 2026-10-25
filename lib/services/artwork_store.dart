import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  bool get hasLocalVideo => videoPath != null && !videoPath!.startsWith('http');
}

/// 本地相册：图片/视频直存 + wishes.json 索引。
///
/// 写入纪律：
/// - 所有文件先写 .tmp 再 rename（原子替换，写一半崩溃不毁索引）；
/// - 全部写操作串行化（快速连续保存/删除不会交错覆盖 wishes.json）。
class ArtworkStore {
  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/artworks');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static final Map<String, Artwork> _index = {};
  static bool _loaded = false;

  // ---- 写操作串行化队列（save/delete/list 首次加载都走这里）----
  static Future<void> _queue = Future.value();

  static Future<T> _serialized<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    // 队列链自身不因异常中断
    _queue = result.then((_) {}, onError: (Object e) => debugPrint('ArtworkStore: $e'));
    return result;
  }

  /// 保存作品，返回条目。videoBytes 优先；否则 videoUrl 记入索引在线播。
  static Future<Artwork> save({
    required List<int> pngBytes,
    required String wish,
    List<int>? videoBytes,
    String? videoUrl,
  }) =>
      _serialized(() => _save(pngBytes: pngBytes, wish: wish, videoBytes: videoBytes, videoUrl: videoUrl));

  static Future<Artwork> _save({
    required List<int> pngBytes,
    required String wish,
    List<int>? videoBytes,
    String? videoUrl,
  }) async {
    final dir = await _dir();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final png = File('${dir.path}/$id.png');
    await _writeBytesAtomic(png, pngBytes);

    String? videoPath;
    if (videoBytes != null) {
      final mp4 = File('${dir.path}/$id.mp4');
      await _writeBytesAtomic(mp4, videoBytes);
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
  static Future<List<Artwork>> list() => _serialized(() async {
        if (!_loaded) {
          _loaded = true;
          final dir = await _dir();
          final wishes = await _loadWishes();
          final pngs = dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.png'));
          for (final f in pngs) {
            final id = idFromPngPath(f.path);
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
      });

  static Future<void> delete(Artwork art) =>
      _serialized(() => _delete(art));

  static Future<void> _delete(Artwork art) async {
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

  /// 从 png 路径解析作品 id。Windows 路径是 `\` 分隔，
  /// 不能只按 `/` 切（否则 id 解析失败 → 愿望/视频关联全丢）。
  @visibleForTesting
  static String idFromPngPath(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    return name.endsWith('.png') ? name.substring(0, name.length - 4) : name;
  }

  // ---- wishes.json：{id: 愿望文本, "id.video": url} ----

  static Future<Map<String, String>> _loadWishes() async {
    try {
      final f = File('${(await _dir()).path}/wishes.json');
      if (!await f.exists()) return {};
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (e) {
      debugPrint('wishes.json 解析失败（忽略并重建）：$e');
      return {};
    }
  }

  static Future<void> _writeWishes(Map<String, String> m) async {
    final f = File('${(await _dir()).path}/wishes.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(m), flush: true);
    await tmp.rename(f.path);
  }

  static Future<void> _writeBytesAtomic(File f, List<int> bytes) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
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
