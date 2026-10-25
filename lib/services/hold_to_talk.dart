import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 按住录音控制器：释放停止，返回 m4a 字节（ASR 友好格式）。
///
/// recorder 懒创建：构造时触碰原生插件会在测试环境炸
/// MissingPluginException（与 SystemSpeechService 同理）。
///
/// [start] 不抛异常：权限被拒 / 启动失败返回 false，调用方走兜底话术，
/// 避免 UI 卡死在"聆听中"状态。
class HoldToTalk {
  AudioRecorder? _recorder;
  String? _path;
  DateTime? _startedAt;
  Timer? _maxTimer;
  bool _autoStopped = false;

  /// 录音短于此视为误触。
  static const Duration minDuration = Duration(milliseconds: 800);

  /// 录音长于此自动截停（防孩子按住几分钟产出超大文件）。
  static const Duration maxDuration = Duration(seconds: 30);

  Future<AudioRecorder> _ensureRecorder() async => _recorder ??= AudioRecorder();

  /// 启动录音。返回 false = 权限被拒或启动失败。
  Future<bool> start() async {
    try {
      final rec = await _ensureRecorder();
      if (!await rec.hasPermission()) {
        debugPrint('HoldToTalk: 麦克风权限未授予');
        return false;
      }
      final dir = await getTemporaryDirectory();
      _path = '${dir.path}/wish_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _startedAt = DateTime.now();
      _autoStopped = false;
      await rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc, // m4a：豆包 ASR 支持
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _path!,
      );
      _maxTimer = Timer(maxDuration, () async {
        _autoStopped = true;
        try {
          await _recorder?.stop();
        } catch (e) {
          debugPrint('HoldToTalk: 超时自动截停失败：$e');
        }
      });
      return true;
    } catch (e) {
      debugPrint('HoldToTalk: 录音启动失败：$e');
      _path = null;
      _startedAt = null;
      return false;
    }
  }

  /// 返回 null = 录得太短（多半是误触）或录音机不可用。
  Future<Uint8List?> stop() async {
    _maxTimer?.cancel();
    _maxTimer = null;
    final p = _path;
    _path = null;
    final started = _startedAt;
    _startedAt = null;
    final rec = _recorder;
    if (rec == null || p == null) return null;
    try {
      if (!_autoStopped) await rec.stop();
    } catch (e) {
      debugPrint('HoldToTalk: 停止录音异常（多半已停止）：$e');
    }
    _autoStopped = false;
    final f = File(p);
    if (!await f.exists()) return null;
    // 用实际时长判定误触（比按文件字节数猜测稳定，编码码率会漂移）
    final tooShort = started != null &&
        DateTime.now().difference(started) < minDuration;
    if (tooShort) {
      await f.delete().catchError((_) => f);
      return null;
    }
    try {
      final bytes = await f.readAsBytes();
      // 读取完毕即清理临时文件，不依赖系统清扫
      unawaited(f.delete().catchError((_) => f));
      return bytes;
    } catch (e) {
      debugPrint('HoldToTalk: 录音读取失败：$e');
      return null;
    }
  }

  /// 页面销毁时调用：停录 + 释放原生资源（孩子按住麦克风时退出页面）。
  void dispose() {
    _maxTimer?.cancel();
    _maxTimer = null;
    final rec = _recorder;
    _recorder = null;
    _path = null;
    _startedAt = null;
    if (rec == null) return;
    unawaited(() async {
      try {
        await rec.stop();
      } catch (_) {/* 未在录音 */}
      try {
        await rec.dispose();
      } catch (_) {/* 已释放 */}
    }());
  }
}
