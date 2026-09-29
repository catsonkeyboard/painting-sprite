import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:painting_sprite/magic/magic_show.dart';
import 'package:painting_sprite/services/speech_service.dart';
import 'package:painting_sprite/ui/kid_ui.dart';

/// 屏 ③：魔法屏 —— 许愿变动画。
///
/// W1 范围：作品预览（本地动画扭起来）+ 4 个预设愿望大按钮 + TTS 演出。
/// W3 接入：语音许愿（ASR→LLM→可灵视频）+ 全链路降级。
class MagicScreen extends StatefulWidget {
  const MagicScreen({super.key, required this.pngBytes, required this.speech});

  final Uint8List pngBytes;
  final SpeechService speech;

  @override
  State<MagicScreen> createState() => _MagicScreenState();
}

enum _MagicPhase { idle, casting, done, fallback }

class _MagicScreenState extends State<MagicScreen> {
  _MagicPhase _phase = _MagicPhase.idle;
  WishType _wish = WishType.dance;

  Future<void> _cast(WishType wish) async {
    if (_phase == _MagicPhase.casting) return;
    setState(() {
      _wish = wish;
      _phase = _MagicPhase.casting;
    });
    await widget.speech.speak(MagicPhrases.casting);
    // W3：这里接入云端视频链路（ASR→LLM→可灵图生视频）。
    // W1：本地动画演出就是魔法本身——2.5 秒"施法"后完成。
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;
    setState(() => _phase = _MagicPhase.done);
    await widget.speech.speak(MagicPhrases.done);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 施法氛围粒子
          if (_phase == _MagicPhase.casting) const MagicParticles(count: 28),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: MagicShow(
                      wish: _wish,
                      autoPlay: _phase != _MagicPhase.idle,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            if (_phase != _MagicPhase.idle)
                              BoxShadow(
                                color: const Color(0xFF7C4DFF).withValues(alpha: 0.4),
                                blurRadius: 40,
                                spreadRadius: 8,
                              ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.memory(
                            widget.pngBytes,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  switch (_phase) {
                    _MagicPhase.idle => '✨ ${_wish.emoji} ${_wish.label} ✨',
                    _MagicPhase.casting => '🌀 ${MagicPhrases.casting}',
                    _MagicPhase.done => '🎉 ${MagicPhrases.done}',
                    _MagicPhase.fallback => '💫 ${MagicPhrases.fallback}',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5D4037),
                  ),
                ),
                const SizedBox(height: 12),
                // 4 个预设愿望大按钮（语音按钮 W3 接麦克风后加入）
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final w in WishType.values)
                        KidUi.bigButton(
                          size: KidUi.minTouch + 8,
                          color: _wish == w && _phase != _MagicPhase.idle
                              ? const Color(0xFF7C4DFF)
                              : Colors.white,
                          onTap: () => _cast(w),
                          child: Text(w.emoji, style: const TextStyle(fontSize: 34)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
