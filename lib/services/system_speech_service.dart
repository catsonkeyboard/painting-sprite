import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'package:painting_sprite/services/speech_service.dart';

/// flutter_tts 真实实现（四端系统语音）。
///
/// 初始化懒执行且全程容错：测试环境（无原生插件）不炸，
/// 桌面端 TTS 不可用时静默——零文字 UI 还有视觉反馈兜底。
class SystemSpeechService implements SpeechService {
  final FlutterTts _tts = FlutterTts();
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    _configured = true;
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.45); // 童趣慢速
      await _tts.setPitch(1.3); // 高音调
    } catch (_) {/* 插件缺失（测试/不支持平台）静默 */}
  }

  @override
  Future<void> speak(String text) async {
    try {
      await _ensureConfigured();
      await _tts.speak(text);
    } catch (_) {/* TTS 失败静默 */}
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
