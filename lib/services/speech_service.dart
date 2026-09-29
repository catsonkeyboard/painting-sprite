import 'dart:async';

/// 语音播报服务：TTS 引导 / 喝彩 / 喝彩 / 魔法故事。
///
/// W1 用系统 TTS；W3 接云端童声 TTS 时替换实现，接口不变。
abstract class SpeechService {
  Future<void> speak(String text);
  Future<void> stop();
}

/// 开发/测试用假实现：只记录，不出声。
class FakeSpeechService implements SpeechService {
  final List<String> spoken = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async {}
}

/// 童趣话术库：全部零文字 UI 的"声音界面"。
class MagicPhrases {
  static const welcome = '欢迎来到涂鸦精灵！画一个小伙伴，让它活过来吧！';
  static const goDraw = '用你的手指画一个小伙伴吧！';
  static const toMagic = '哇，画好啦！我们去给它施魔法吧！';
  static const askWish = '按住大按钮，说出你的愿望！';
  static const casting = '小精灵正在施魔法，咕噜咕噜变！';
  static const done = '哇！它活过来啦！';
  static const fallback = '小精灵的魔法还在路上，它先自己扭一扭！';
  static const tryAgain = '小精灵没听清，再说一遍好不好？';
}
