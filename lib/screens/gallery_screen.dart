import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:painting_sprite/services/artwork_store.dart';

/// 作品相册：缩略图网格 → 详情（播放动画 / 看原图 / 删除）。
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<Artwork> _items = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await ArtworkStore.list();
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🖼️ 我的画作'),
        backgroundColor: const Color(0xFFFFF8E7),
        foregroundColor: const Color(0xFF5D4037),
      ),
      body: _items.isEmpty
          ? const Center(
              child: Text(
                '还没有画作哦，去画一幅吧！',
                style: TextStyle(fontSize: 20, color: Color(0xFF8D6E63)),
              ),
            )
          : GridView.count(
              crossAxisCount: 4,
              padding: const EdgeInsets.all(12),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                for (final art in _items)
                  _Thumb(
                    art: art,
                    onTap: () => _openDetail(art),
                  ),
              ],
            ),
    );
  }

  void _openDetail(Artwork art) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DetailScreen(art: art, onDelete: _reload),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.art, required this.onTap});

  final Artwork art;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFE082), width: 3),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: Image.file(File(art.pngPath), fit: BoxFit.contain),
            ),
            if (art.hasVideo)
              const Positioned(
                right: 4,
                bottom: 4,
                child: Text('🎬', style: TextStyle(fontSize: 18)),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailScreen extends StatefulWidget {
  const _DetailScreen({required this.art, required this.onDelete});

  final Artwork art;
  final Future<void> Function() onDelete;

  @override
  State<_DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<_DetailScreen> {
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    final v = widget.art.videoPath;
    if (v != null) {
      final ctrl = v.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(v))
          : VideoPlayerController.file(File(v));
      _video = ctrl;
      ctrl.initialize().then((_) {
        if (mounted) {
          setState(() {});
          ctrl.setLooping(true);
          ctrl.play();
        }
      });
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    await ArtworkStore.delete(widget.art);
    await widget.onDelete();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.art.wish.isEmpty ? '我的画作' : '愿望：${widget.art.wish}'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 28),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: Center(
        child: v != null && v.value.isInitialized
            ? AspectRatio(
                aspectRatio: v.value.aspectRatio,
                child: VideoPlayer(v),
              )
            : InteractiveViewer(
                child: Image.file(File(widget.art.pngPath), fit: BoxFit.contain),
              ),
      ),
    );
  }
}
