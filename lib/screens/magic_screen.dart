import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:painting_sprite/magic/magic_show.dart';
import 'package:painting_sprite/magic/wish_action.dart';
import 'package:painting_sprite/services/ai_service.dart';
import 'package:painting_sprite/services/artwork_store.dart';
import 'package:painting_sprite/services/hold_to_talk.dart';
import 'package:painting_sprite/services/speech_service.dart';
import 'package:painting_sprite/services/wish_quota.dart';
import 'package:painting_sprite/ui/kid_ui.dart';

/// 屏 ③：魔法屏 —— 许愿变 5 秒动画（W3 全链路版）。
///
/// 链路：按住说话 → ASR → LLM(愿望+提示词) → 方舟 Seedance 视频（异步 30s~3min）
/// 等待期：本地动画扭起来 + 粒子 + TTS 讲故事（魔法演出）
/// 降级：视频失败 → 本地动画兜底；没听清 → 预设愿望大按钮。
class MagicScreen extends StatefulWidget {
  const MagicScreen({
    super.key,
    required this.pngBytes,
    required this.ai,
    required this.speech,
    this.knownSubject,
  });

  final Uint8List pngBytes;
  final AiService ai;
  final SpeechService speech;

  /// 已知画作主体（内置线稿标签）：命中预制动作集时跳过 LLM 看图分析。
  final String? knownSubject;

  @override
  State<MagicScreen> createState() => _MagicScreenState();
}

enum _Phase { idle, listening, casting, videoReady, fallback }

class _MagicScreenState extends State<MagicScreen> {
  _Phase _phase = _Phase.idle;
  WishType _wish = WishType.dance;
  bool _confetti = false;

  /// 看图分析结果：null = 未完成/失败 → 按钮用默认动作集。
  ArtworkAnalysis? _analysis;
  int? _activeActionIndex; // 当前施法动作高亮
  bool _analyzing = true; // 进屏即分析（成功/失败都结束）

  final HoldToTalk _talk = HoldToTalk();
  VideoPlayerController? _video;
  Timer? _storyTimer;

  /// 施法序号：新许愿 / 页面销毁让旧链路的后续操作全部作废。
  int _castSeq = 0;

  @override
  void initState() {
    super.initState();
    // 内置线稿主体已知：直接用预制动作集（零延迟零成本），
    // 只有自由涂鸦/云端生成才走 LLM 看图分析。
    final preset = widget.knownSubject == null
        ? null
        : ArtworkAnalysis.presetFor(widget.knownSubject!);
    if (preset != null) {
      _analysis = preset;
      _analyzing = false;
      debugPrint('[画作分析] 内置线稿命中预制集：${preset.subject}');
      unawaited(widget.speech.speak('哇，我看到了${preset.subject}！选一个魔法吧！'));
    } else {
      unawaited(_analyzeArtwork());
    }
  }

  List<WishAction> get _actions =>
      _analysis?.actions ?? ArtworkAnalysis.defaultActions;

  /// 看图分析：成功换按钮，失败保默认（不阻塞、不打扰）。
  Future<void> _analyzeArtwork() async {
    try {
      final a = await widget.ai.analyzeArtwork(widget.pngBytes);
      if (a == null) {
        debugPrint('[画作分析] 未得到有效结果，保留默认按钮');
        return;
      }
      debugPrint(
          '[画作分析] 主体=${a.subject} 动作=${a.actions.map((x) => '${x.label}${x.emoji}').join('/')}');
      if (mounted) {
        setState(() => _analysis = a);
        // 语音播报让"看懂了"被听见（仅空闲时，不打断施法）
        if (_phase == _Phase.idle) {
          unawaited(widget.speech.speak('哇，我看到了$a.subject！选一个魔法吧！'));
        }
      }
    } catch (e) {
      debugPrint('[画作分析] 失败，保留默认按钮：$e');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  void dispose() {
    _castSeq++; // 让在途的云端轮询立刻取消
    _stopStory();
    _stopWaitClock();
    _talk.dispose(); // 孩子按住麦克风时退出 → 停录并释放
    unawaited(_video?.dispose());
    _video = null;
    super.dispose();
  }

  // ---- 等待期 TTS 小故事（设计 §2.3：持续陪伴，不是只播一句）----

  void _startStory() {
    _stopStory();
    var i = 0;
    _storyTimer = Timer.periodic(const Duration(seconds: 16), (_) {
      unawaited(widget.speech.speak(MagicPhrases.waitingStories[i++ % MagicPhrases.waitingStories.length]));
    });
  }

  void _stopStory() {
    _storyTimer?.cancel();
    _storyTimer = null;
    _stopWaitClock(); // 施法等待结束（成功/兜底/取消）与故事同步停止
  }

  // ---- 施法等待计时（让"还要等多久"看得见；上限 3 分钟超时兜底）----

  int _waitSec = 0;
  Timer? _waitTimer;

  void _startWaitClock() {
    _stopWaitClock();
    _waitSec = 0;
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _waitSec++);
    });
  }

  void _stopWaitClock() {
    _waitTimer?.cancel();
    _waitTimer = null;
  }

  // ---- 麦克风 ----

  Future<void> _onMicPressed() async {
    if (busy) return;
    setState(() => _phase = _Phase.listening);
    final ok = await _talk.start(); // 不抛异常：失败返回 false
    if (!ok) {
      if (!mounted) return;
      setState(() => _phase = _Phase.idle);
      unawaited(widget.speech.speak(MagicPhrases.micBlocked));
    }
  }

  Future<void> _onMicReleased() async {
    if (!mounted || _phase != _Phase.listening) return;
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
    if (!mounted) return;
    setState(() {
      _phase = _Phase.casting;
      _confetti = false; // 复位：下一次成功才能重新撒花
    });
    try {
      final text = await widget.ai.transcribe(audio);
      if (!mounted) return;
      if (text.trim().isEmpty) throw Exception('没听清');
      await _startMagicShow(text);
    } catch (_) {
      if (!mounted) return;
      await widget.speech.speak(MagicPhrases.tryAgain);
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  /// 动态动作按钮直通车：预生成提示词直用，点击零 LLM 调用。
  Future<void> _castAction(WishAction a, int index) async {
    if (busy) return;
    setState(() {
      _wish = a.anim;
      _activeActionIndex = index;
      _phase = _Phase.casting;
      _confetti = false;
    });
    final subject = _analysis?.subject;
    await _startMagicShow(
      a.label,
      presetPrompt: a.prompt,
      wishForStore: subject == null ? a.label : '$subject${a.label}',
    );
  }

  bool get busy => _phase == _Phase.casting || _phase == _Phase.listening;

  Future<void> _startMagicShow(
    String wishText, {
    String? presetPrompt,
    String? wishForStore,
  }) async {
    final seq = ++_castSeq;
    final storeText = wishForStore ?? wishText;
    debugPrint('[施法] 开始 wish="$wishText"');
    unawaited(widget.speech.speak(MagicPhrases.casting));
    _startStory();
    _startWaitClock();

    // 动作按钮：提示词已预生成，跳过 LLM；语音：LLM + 主体注入
    var videoPrompt = presetPrompt ??
        'a cute doodle character dancing happily, playful children animation style';
    if (presetPrompt == null) {
      try {
        final r = await widget.ai
            .interpretWish(wishText, subject: _analysis?.subject);
        videoPrompt = r.videoPrompt;
        debugPrint('[LLM] 分类=${r.wish} 提示词="$videoPrompt"');
        // LLM 分类结果要立即上屏：等待期动画得跟愿望匹配
        if (mounted && seq == _castSeq) {
          setState(() => _wish = _wishFromLabel(r.wish));
        }
      } catch (e) {
        debugPrint('[LLM] 愿望理解失败，用默认提示词：$e');
      }
    }

    // 家长限流：配额不足 → 直接本地动画（不发起云端任务，不扣钱）
    if (!await WishQuota.spend()) {
      debugPrint('[配额] 今日云端许愿已用完，走本地动画');
      _stopStory();
      if (!mounted || seq != _castSeq) return;
      setState(() => _phase = _Phase.fallback);
      unawaited(widget.speech.speak('今天的云朵魔法用完啦，小精灵给你变本地的！'));
      _saveQuiet(storeText);
      return;
    }
    debugPrint('[配额] 已扣，开始云端视频生成');

    try {
      final videoUrl = await widget.ai.animateDrawing(
        imageBytes: widget.pngBytes,
        videoPrompt: videoPrompt,
        isCancelled: () => !mounted || seq != _castSeq,
      );
      _stopStory();

      // 视频字节优先落盘：云端 URL 会过期，本地 mp4 才是孩子回看的保障
      final videoBytes = await widget.ai.downloadVideoOrNull(videoUrl);
      final bytesDesc = switch (videoBytes) {
        null => '失败（回退 URL 在线播）',
        final b => '成功 ${b.length} 字节',
      };
      debugPrint('[视频] 下载 $bytesDesc');
      Artwork? art;
      try {
        art = await ArtworkStore.save(
          pngBytes: widget.pngBytes,
          wish: storeText,
          videoBytes: videoBytes,
          videoUrl: videoBytes == null ? videoUrl.toString() : null,
        );
      } catch (e) {
        debugPrint('作品保存失败：$e');
      }

      final ctrl = (art != null && art.hasLocalVideo)
          ? VideoPlayerController.file(File(art.videoPath!))
          : VideoPlayerController.networkUrl(videoUrl);
      try {
        await ctrl.initialize().timeout(const Duration(seconds: 20));
        await ctrl.setLooping(true);
      } catch (e) {
        unawaited(ctrl.dispose());
        throw Exception('视频初始化失败：$e'); // 落到下方兜底 + 退还
      }
      if (!mounted || seq != _castSeq) {
        // 作品已存相册不浪费；控制器没人显示了，直接释放
        unawaited(ctrl.dispose());
        return;
      }
      _setVideo(ctrl); // 释放旧控制器（防止二次许愿泄漏 + 旧声音持续播）
      setState(() {
        _phase = _Phase.videoReady;
        _confetti = true;
      });
      unawaited(ctrl.play());
      unawaited(widget.speech.speak(MagicPhrases.done));
    } on AnimationCancelled {
      // 用户退出/重新许愿：停轮询、退配额（孩子没看到视频就不算钱）
      await WishQuota.refund();
      _stopStory();
      _saveQuiet(storeText);
    } catch (e) {
      // 四级降级：本地动画兜底 + 退还配额（孩子没看到视频就不算钱）
      debugPrint('[视频] 生成失败，落本地动画兜底：$e');
      await WishQuota.refund();
      _stopStory();
      if (mounted && seq == _castSeq) {
        setState(() => _phase = _Phase.fallback);
        unawaited(widget.speech.speak(MagicPhrases.fallback));
      }
      _saveQuiet(storeText);
    }
  }

  void _setVideo(VideoPlayerController ctrl) {
    final old = _video;
    _video = ctrl;
    unawaited(old?.dispose());
  }

  /// 静默保存作品（页面可能已卸载，不碰 UI、错误只记日志）。
  void _saveQuiet(String wish) {
    unawaited(() async {
      try {
        await ArtworkStore.save(pngBytes: widget.pngBytes, wish: wish);
      } catch (e) {
        debugPrint('作品保存失败：$e');
      }
    }());
  }

  WishType _wishFromLabel(String s) => switch (s) {
        'dance' => WishType.dance,
        'fly' => WishType.fly,
        'sing' => WishType.sing,
        'run' => WishType.run,
        _ => WishType.dance, // other / 未知类型按默认愿望演出
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 施法中（最长 3 分钟、云端在扣钱）拦截返回键，防止误触作废
      canPop: _phase != _Phase.casting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(widget.speech.speak(MagicPhrases.waitMagic));
      },
      child: Scaffold(
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
            const KidBackButton(), // 施法中由 PopScope 拦截劝等，其余直接返回
          ],
        ),
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
                color: KidUi.magicPurple.withValues(alpha: 0.4),
                blurRadius: 40,
                spreadRadius: 8,
              ),
          ],
        ),
        child: child,
      );

  Widget _buildStatus() {
    final text = switch (_phase) {
      _Phase.idle => _analyzing
          ? '👀 小精灵正在看你的画…'
          : '按住 🎤 许愿，或点下面的魔法按钮',
      _Phase.listening => '👂 小精灵在听…',
      _Phase.casting => '🌀 ${MagicPhrases.casting}（已等 $_waitSec 秒，最多 180 秒）',
      _Phase.videoReady => '🎉 ${MagicPhrases.done}',
      _Phase.fallback => '💫 ${MagicPhrases.fallback}',
    };
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: KidUi.textBrown,
      ),
    );
  }

  Widget _buildWishRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 按住说话大麦克风
        GestureDetector(
          onLongPressStart: (_) => _onMicPressed(),
          onLongPressEnd: (_) => _onMicReleased(),
          onLongPressCancel: _onMicReleased, // 系统打断（来电等）也要正确收尾
          child: KidUi.bigButton(
            size: KidUi.minTouch + 16,
            color: _phase == _Phase.listening ? KidUi.micRecording : KidUi.micBlue,
            onTap: () {
              // 孩子最自然的"点一下"：语音引导改成长按
              if (!busy) unawaited(widget.speech.speak(MagicPhrases.holdMic));
            },
            child: const Text('🎤', style: TextStyle(fontSize: 40)),
          ),
        ),
        for (final (i, a) in _actions.indexed)
          KidUi.bigButton(
            size: KidUi.minTouch + 8,
            color: _activeActionIndex == i && _phase != _Phase.idle
                ? KidUi.magicPurple
                : Colors.white,
            onTap: busy ? () {} : () => _castAction(a, i),
            // emoji + 中文小标签：动态动作换了能一眼看出来
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(a.emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(height: 2),
                Text(
                  a.label,
                  style: const TextStyle(
                      fontSize: 11, color: KidUi.textBrown),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
