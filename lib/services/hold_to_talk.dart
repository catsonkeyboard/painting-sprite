import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 按住录音控制器：释放停止，返回 wav 字节（ASR 友好格式）。
///
/// recorder 懒创建：构造时触碰原生插件会在测试环境炸
/// MissingPluginException（与 SystemSpeechService 同理）。
class HoldToTalk {
  AudioRecorder? _recorder;
  String? _path;

  Future<AudioRecorder> _ensureRecorder() async =>
      _recorder ??= AudioRecorder();

  Future<void> start() async {
    final rec = await _ensureRecorder();
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/wish_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc, // m4a：豆包 ASR 支持
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _path!,
    );
  }

  /// 返回 null = 录得太短（<0.8s，多半是误触）。
  Future<Uint8List?> stop() async {
    final p = _path;
    _path = null;
    final rec = _recorder;
    if (rec == null) return null;
    final file = await rec.stop();
    if (p == null || file == null) return null;
    final f = File(p);
    if (!await f.exists()) return null;
    final stat = await f.length();
    // aac 16k 单声道 ≈ 16KB/s，太短视为误触
    if (stat < 12000) {
      await f.delete().catchError((_) => f);
      return null;
    }
    return f.readAsBytes();
  }
}
