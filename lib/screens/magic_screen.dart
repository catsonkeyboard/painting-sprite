import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:painting_sprite/magic/magic_show.dart';
import 'package:painting_sprite/services/ai_service.dart';
import 'package:painting_sprite/services/artwork_store.dart';
import 'package:painting_sprite/services/hold_to_talk.dart';
import 'package:painting_sprite/services/speech_service.dart';
import 'package:painting_sprite/services/wish_quota.dart';
import 'package:painting_sprite/ui/kid_ui.dart';

/// 屏 ③：魔法屏 —— 许愿变 5 秒动画（W3 全链路版）。
///
/// 链路：按住说话 → ASR → LLM(愿望+提示词) → 可灵视频（异步 30s~3min）
/// 等待期：本地动画扭起来 + 粒子 + TTS 讲故事（魔法演出）
/// 降级：视频失败 → 本地动画兜底；没听清 → 预设愿望大按钮。
class MagicScreen extends StatefulWidget {
  const MagicScreen({
    super.key,
    required this.pngBytes,
    required this.ai,
    required this.speech,
  });

  final Uint8List pngBytes;
  final AiService ai;
  final SpeechService speech;

  @override
  State<MagicScreen> createState() => _MagicScreenState();
}

enum _Phase { idle, listening, casting, videoReady, fallback }

class _MagicScreenState extends State<MagicScreen> {
  _Phase _phase = _Phase.idle;
  WishType _wish = WishType.dance;
  bool _confetti = false;

  final HoldToTalk _talk = HoldToTalk();
  VideoPlayerController? _video;

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _onMicReleased() async {
    final audio = await _talk.stop();
    if (audio == null) {
      // 太短 = 误触
      await widget.speech.speak(MagicPhrases.tryAgain);
      if (mounted) setState(() => _phase = _Phase.idle);
      return;
    }
    await _castWithAudio(audio);
  }

  Future<void> _castWithAudio(Uint8List audio) async {
    setState(() => _phase = _Phase.casting);
    try {
      final text = await widget.ai.transcribe(audio);
      if (text.trim().isEmpty) throw Exception('empty');
      await _startMagicShow(text);
    } catch (_) {
      await widget.speech.speak(MagicPhrases.tryAgain);
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  /// 预设按钮直通车。
  Future<void> _castPreset(WishType w) async {
    if (_phase == _Phase.casting || _phase == _Phase.listening) return;
    setState(() {
      _wish = w;
      _phase = _Phase.casting;
    });
    await _startMagicShow('让它${w.label}');
  }

  Future<void> _startMagicShow(String wishText) async {
    unawaited(widget.speech.speak(MagicPhrases.casting));

    String videoPrompt = 'a cute doodle character dancing happily, '
        'playful children animation style';
    try {
      final r = await widget.ai.interpretWish(wishText);
      videoPrompt = r.videoPrompt;
      _wish = _wishFromLabel(r.wish);
    } catch (_) {/* LLM 失败用默认提示词 */}

    // 家长限流：配额不足 → 直接本地动画（不发起云端任务，不扣钱）
    if (!await WishQuota.spend()) {
      if (!mounted) return;
      setState(() => _phase = _Phase.fallback);
      unawaited(widget.speech.speak('今天的云朵魔法用完啦，小精灵给你变本地的！'));
      unawaited(ArtworkStore.save(pngBytes: widget.pngBytes, wish: wishText));
      return;
    }

    try {
      final videoUrl = await widget.ai.animateDrawing(
        imageBytes: widget.pngBytes,
        videoPrompt: videoPrompt,
      );
      final ctrl = VideoPlayerController.networkUrl(videoUrl);
      await ctrl.initialize();
      await ctrl.setLooping(true);
      // spend 已扣的配额成功消费，不退还
      if (!mounted) return;
      setState(() {
        _video = ctrl;
        _phase = _Phase.videoReady;
        _confetti = true;
      });
      unawaited(ctrl.play());
      unawaited(widget.speech.speak(MagicPhrases.done));
      unawaited(ArtworkStore.save(
        pngBytes: widget.pngBytes,
        wish: wishText,
        videoUrl: videoUrl.toString(),
      ));
    } catch (_) {
      // 四级降级：本地动画兜底 + 退还配额（孩子没看到视频就不算钱）
      await WishQuota.refund();
      if (!mounted) return;
      setState(() => _phase = _Phase.fallback);
      unawaited(widget.speech.speak(MagicPhrases.fallback));
      unawaited(ArtworkStore.save(pngBytes: widget.pngBytes, wish: wishText));
    }
  }

  WishType _wishFromLabel(String s) => switch (s) {
        'fly' => WishType.fly,
        'sing' => WishType.sing,
        'run' => WishType.run,
        _ => WishType.dance,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_phase == _Phase.casting) const MagicParticles(count: 28),
          if (_confetti) const ConfettiBurst(),
          SafeArea(
            child: Column(
              children: [
                Expanded(child: Center(child: _buildStage())),
                _buildStatus(),
                const SizedBox(height: 12),
                _buildWishRow(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStage() {
    if (_phase == _Phase.videoReady && _video != null) {
      return AspectRatio(
        aspectRatio: _video!.value.aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: VideoPlayer(_video!),
        ),
      );
    }
    return MagicShow(
      wish: _wish,
      autoPlay: _phase != _Phase.idle,
      child: _glowWrap(
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.memory(widget.pngBytes, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _glowWrap(Widget child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            if (_phase != _Phase.idle)
              BoxShadow(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.4),
                blurRadius: 40,
                spreadRadius: 8,
              ),
          ],
        ),
        child: child,
      );

  Widget _buildStatus() {
    final text = switch (_phase) {
      _Phase.idle => '按住 🎤 许愿，或点下面的魔法按钮',
      _Phase.listening => '👂 小精灵在听…',
      _Phase.casting => '🌀 小精灵正在施魔法，咕噜咕噜变！',
      _Phase.videoReady => '🎉 它活过来啦！',
      _Phase.fallback => '💫 ${MagicPhrases.fallback}',
    };
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Color(0xFF5D4037),
      ),
    );
  }

  Widget _buildWishRow() {
    final busy = _phase == _Phase.casting || _phase == _Phase.listening;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 按住说话大麦克风
        GestureDetector(
          onLongPressStart: (_) async {
            if (busy) return;
            setState(() => _phase = _Phase.listening);
            await _talk.start();
          },
          onLongPressEnd: (_) => _onMicReleased(),
          child: KidUi.bigButton(
            size: KidUi.minTouch + 16,
            color: _phase == _Phase.listening
                ? const Color(0xFFFF7043)
                : const Color(0xFF81D4FA),
            onTap: () {},
            child: const Text('🎤', style: TextStyle(fontSize: 40)),
          ),
        ),
        for (final w in WishType.values)
          KidUi.bigButton(
            size: KidUi.minTouch + 8,
            color: _wish == w && _phase != _Phase.idle
                ? const Color(0xFF7C4DFF)
                : Colors.white,
            onTap: busy ? () {} : () => _castPreset(w),
            child: Text(w.emoji, style: const TextStyle(fontSize: 34)),
          ),
      ],
    );
  }
}
