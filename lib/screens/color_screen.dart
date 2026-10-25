import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:painting_sprite/coloring/flood_filler.dart';
import 'package:painting_sprite/services/ai_service.dart';
import 'package:painting_sprite/services/hold_to_talk.dart';
import 'package:painting_sprite/services/speech_service.dart';
import 'package:painting_sprite/ui/kid_ui.dart';

/// 内置线稿库：离线兜底 + 快捷入口（零文字：缩略图即入口）。
class LineArtLibrary {
  /// (资源, 标签, 命中同义词)：孩子说"小白兔"也要命中"兔子"线稿。
  static const List<(String asset, String label, List<String> aliases)> items = [
    ('assets/lineart/dinosaur.png', '恐龙', ['恐龙', '龙']),
    ('assets/lineart/cat.png', '小猫', ['小猫', '猫咪', '猫']),
    ('assets/lineart/rabbit.png', '兔子', ['兔子', '小兔', '兔']),
    ('assets/lineart/unicorn.png', '独角兽', ['独角兽']),
    ('assets/lineart/rocket.png', '火箭', ['火箭']),
    ('assets/lineart/goldfish.png', '金鱼', ['金鱼']),
    ('assets/lineart/butterfly.png', '蝴蝶', ['蝴蝶']),
    ('assets/lineart/house.png', '房子', ['房子', '家']),
  ];

  /// 识别文本 → 命中的线稿（未命中返回 null，走云端生成）。
  static (String, String)? match(String text) {
    for (final (asset, label, aliases) in items) {
      if (aliases.any(text.contains)) return (asset, label);
    }
    return null;
  }
}

/// 屏 ②：涂色屏 —— 选线稿（内置库 / 语音生成）→ 点选大色块填色。
class ColorScreen extends StatefulWidget {
  const ColorScreen({
    super.key,
    required this.ai,
    required this.speech,
    required this.onDone,
  });

  final AiService ai;
  final SpeechService speech;

  /// 完成回调：PNG + 已知主体（内置线稿的标签；自由/云端生成为 null，
  /// 魔法屏据此直接用预制动作集或走 LLM 看图）。
  final void Function(Uint8List png, String? knownSubject) onDone;

  @override
  State<ColorScreen> createState() => _ColorScreenState();
}

enum _ColorPhase { pickLibrary, coloring }

class _ColorScreenState extends State<ColorScreen> {
  _ColorPhase _phase = _ColorPhase.pickLibrary;
  Color _selected = KidUi.palette.first;

  // 涂色画布状态
  ui.Image? _image;
  Uint8List? _pixels;
  int _imgW = 0, _imgH = 0;
  final List<Uint8List> _undoStack = [];

  /// 全图快照级撤销的上限（1024² 图约 4MB/张，防低端设备 OOM）。
  static const int maxUndo = 10;

  bool _busyGenerating = false;
  bool _listening = false;
  bool _exporting = false;
  String? _knownSubject; // 选中的内置线稿主体（云端生成/自绘为 null）
  final HoldToTalk _talk = HoldToTalk();

  @override
  void initState() {
    super.initState();
    widget.speech.speak(MagicPhrases.goColor); // 进入引导
  }

  @override
  void dispose() {
    _talk.dispose();
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  /// 帧结束后释放被替换的旧图（当帧渲染仍可能引用它）。
  void _disposeImageLater(ui.Image? old) {
    if (old == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
    });
  }

  Future<void> _pickAsset(String asset) async {
    // 内置线稿主体已知 → 魔法屏直接用预制动作集
    _knownSubject = LineArtLibrary.items
        .where((it) => it.$1 == asset)
        .map((it) => it.$2)
        .firstOrNull;
    try {
      final data = await rootBundle.load(asset);
      await _loadToBuffer(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (e) {
      debugPrint('线稿加载失败 $asset：$e');
      if (mounted) unawaited(widget.speech.speak(MagicPhrases.tryAgain));
    }
  }

  Future<void> _loadToBuffer(Uint8List pngBytes) async {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) {
      image.dispose();
      codec.dispose();
      return;
    }
    if (!mounted) {
      image.dispose();
      codec.dispose();
      return;
    }
    final old = _image;
    setState(() {
      _image = image;
      _pixels = Uint8List.fromList(bd.buffer.asUint8List());
      _imgW = image.width;
      _imgH = image.height;
      _undoStack.clear();
      _phase = _ColorPhase.coloring;
    });
    _disposeImageLater(old);
    codec.dispose();
  }

  // ---------- 语音线稿：真录音 → ASR → 内置库/Seedream ----------

  Future<void> _startVoice() async {
    if (_busyGenerating || _listening) return;
    setState(() {
      _busyGenerating = true;
      _listening = true;
    });
    await widget.speech.speak('说出你想画的小伙伴吧！');
    final ok = await _talk.start(); // 不抛异常：失败返回 false
    if (!ok) {
      if (!mounted) return;
      // 关键：busy 一并复位，否则麦克风按钮永久转圈、语音入口锁死
      setState(() {
        _listening = false;
        _busyGenerating = false;
      });
      unawaited(widget.speech.speak(MagicPhrases.micBlocked));
    }
  }

  Future<void> _finishVoice() async {
    if (!_listening) return;
    if (mounted) setState(() => _listening = false);
    final audio = await _talk.stop();
    if (audio == null) {
      // 录音太短 = 误触
      await widget.speech.speak(MagicPhrases.tryAgain);
      if (mounted) setState(() => _busyGenerating = false);
      return;
    }
    await _generateFromVoice(audio);
  }

  Future<void> _generateFromVoice(Uint8List audio) async {
    String text = '';
    try {
      text = await widget.ai.transcribe(audio);
    } catch (e) {
      debugPrint('ASR 失败：$e');
      text = '';
    }

    // 1. 快速路径：识别文本命中内置线稿库（零成本零等待）
    final match = LineArtLibrary.match(text);
    if (match != null) {
      await widget.speech.speak('好的，${match.$2}来啦！');
      await _pickAsset(match.$1);
      if (mounted) setState(() => _busyGenerating = false);
      return;
    }

    // 2. 云端生成：Seedream 出 2 张二选一（失败透传到这里的 catch）
    if (text.trim().isNotEmpty) {
      await widget.speech.speak('小精灵正在画$text，等它一下下！');
      try {
        final arts = await widget.ai.generateLineArt(text);
        if (mounted) {
          setState(() => _busyGenerating = false);
          await _pickOne(arts, text);
          return;
        }
      } catch (e) {
        debugPrint('云端线稿生成失败，落内置库兜底：$e');
      }
    }

    // 3. 兜底：没听清/生成失败 → 第一张内置线稿
    await widget.speech.speak(MagicPhrases.lineArtFallback);
    await _pickAsset(LineArtLibrary.items.first.$1);
    if (mounted) setState(() => _busyGenerating = false);
  }

  /// 二选一大图对话框（云端生成，主体未知）。
  Future<void> _pickOne(List<Uint8List> arts, String subject) async {
    _knownSubject = null; // 云端生成的图没有预制动作
    if (arts.length != 2 || arts.isEmpty) {
      if (arts.isNotEmpty) await _loadToBuffer(arts.first);
      return;
    }
    final choice = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PickOneDialog(images: arts, subject: subject),
    );
    if (choice != null) await _loadToBuffer(choice);
  }

  void _fillAt(Offset localPos, Size canvasSize) {
    if (_pixels == null || _image == null) return;
    // 画布按 contain 缩放：换算图片坐标系
    final scale = _fitContainScale(canvasSize);
    final imgW = _imgW * scale, imgH = _imgH * scale;
    final offX = (canvasSize.width - imgW) / 2, offY = (canvasSize.height - imgH) / 2;
    final x = ((localPos.dx - offX) / scale).round().clamp(0, _imgW - 1);
    final y = ((localPos.dy - offY) / scale).round().clamp(0, _imgH - 1);

    _undoStack.add(Uint8List.fromList(_pixels!));
    if (_undoStack.length > maxUndo) _undoStack.removeAt(0);

    final filler = FloodFiller(_imgW, _imgH, _pixels!);
    // 40：吃掉抗锯齿浅灰边，又不至于击穿细线（黑线另有绝对屏障兜底）
    final n = filler.fill(x, y, _selected, tolerance: 40);
    if (n == 0) {
      _undoStack.removeLast();
      return;
    }
    _updateImage();
  }

  /// FittedBox(contain) 的缩放系数。
  double _fitContainScale(Size box) {
    final s = _imgW / _imgH, bs = box.width / box.height;
    return s > bs ? box.width / _imgW : box.height / _imgH;
  }

  Future<void> _updateImage() async {
    final image = await _decodePixels();
    if (!mounted || image == null) {
      image?.dispose();
      return;
    }
    final old = _image;
    setState(() => _image = image);
    _disposeImageLater(old);
  }

  Future<ui.Image?> _decodePixels() {
    final completer = Completer<ui.Image?>();
    ui.decodeImageFromPixels(
      _pixels!,
      _imgW,
      _imgH,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() => _pixels = _undoStack.removeLast());
    _updateImage();
  }

  Future<void> _finish() async {
    if (_exporting || _image == null) return;
    _exporting = true;
    try {
      final data = await _image!.toByteData(format: ui.ImageByteFormat.png);
      if (data != null) {
        widget.onDone(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          _knownSubject,
        );
      }
    } catch (e) {
      debugPrint('涂色导出失败：$e');
      unawaited(widget.speech.speak(MagicPhrases.tryAgain));
    } finally {
      _exporting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(child: _buildBody()),
                _buildBottomBar(),
              ],
            ),
          ),
          const KidBackButton(), // 桌面端没有系统返回键
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _ColorPhase.pickLibrary:
        return _buildLibraryGrid();
      case _ColorPhase.coloring:
        return _buildColoringCanvas();
    }
  }

  Widget _buildLibraryGrid() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: GestureDetector(
            onLongPressStart: (_) => _startVoice(),
            onLongPressEnd: (_) => _finishVoice(),
            onLongPressCancel: _finishVoice,
            child: KidUi.bigButton(
              size: 80,
              color: _listening ? KidUi.micRecording : KidUi.micBlue,
              onTap: () {
                if (!_busyGenerating && !_listening) {
                  unawaited(widget.speech.speak(MagicPhrases.goColor));
                }
              },
              child: _busyGenerating
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : const Text('🎤', style: TextStyle(fontSize: 36)),
            ),
          ),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 4,
            padding: const EdgeInsets.all(12),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              for (final it in LineArtLibrary.items)
                GestureDetector(
                  onTap: () => _pickAsset(it.$1),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: KidUi.cardYellow, width: 4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(it.$1, fit: BoxFit.contain),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildColoringCanvas() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _fillAt(d.localPosition, canvasSize),
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox(
                  width: canvasSize.width,
                  height: canvasSize.height,
                  child: _image == null
                      ? null
                      : Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: _imgW.toDouble(),
                              height: _imgH.toDouble(),
                              child: RawImage(image: _image!),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    if (_phase != _ColorPhase.coloring) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: KidUi.minTouch,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in KidUi.palette)
                  GestureDetector(
                    onTap: () => setState(() => _selected = c),
                    child: SizedBox(
                      width: KidUi.minTouch,
                      height: KidUi.minTouch,
                      child: Center(
                        child: Container(
                          width: KidUi.minTouch - 12,
                          height: KidUi.minTouch - 12,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selected == c
                                  ? KidUi.magicPurple
                                  : Colors.grey.shade300,
                              width: 4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              KidUi.bigButton(
                size: KidUi.minTouch,
                color: Colors.white,
                onTap: _undo,
                child: const Icon(Icons.undo, size: 32, color: KidUi.inkDark),
              ),
              KidUi.bigButton(
                size: KidUi.minTouch,
                color: Colors.white,
                onTap: () => setState(() => _phase = _ColorPhase.pickLibrary),
                child: const Icon(Icons.grid_view, size: 30, color: KidUi.inkDark),
              ),
              KidUi.bigButton(
                size: KidUi.minTouch,
                color: KidUi.magicPurple,
                onTap: _finish,
                child: const Icon(Icons.auto_awesome, size: 34, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 二选一大图对话框：两张 Seedream 线稿，点哪张用哪张。
class _PickOneDialog extends StatelessWidget {
  const _PickOneDialog({required this.images, required this.subject});

  final List<Uint8List> images;
  final String subject;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: KidUi.bgCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '选一个"$subject"涂色吧！',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: KidUi.textBrown,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final img in images)
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(img),
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: KidUi.cardYellow, width: 5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Image.memory(img, fit: BoxFit.contain),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
