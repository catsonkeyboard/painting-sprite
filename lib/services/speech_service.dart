import 'dart:async';

/// 语音播报服务：TTS 引导 / 喝彩 / 魔法故事。
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
  static const goColor = '按住麦克风说出你想画的，或者点下面的图片！';
  static const toMagic = '哇，画好啦！我们去给它施魔法吧！';
  static const askWish = '按住大按钮，说出你的愿望！';
  static const casting = '小精灵正在施魔法，咕噜咕噜变！';
  static const done = '哇！它活过来啦！';
  static const fallback = '小精灵的魔法还在路上，它先自己扭一扭！';
  static const tryAgain = '小精灵没听清，再说一遍好不好？';
  // 画板场景
  static const drawFirst = '先画一画，再施魔法吧！';
  static const stayDrawing = '画还没施魔法呢！';
  // 麦克风场景
  static const micBlocked = '小精灵的耳朵还没打开，用下面的魔法按钮吧！';
  static const holdMic = '按住麦克风不放，再说出你的愿望哦！';
  static const waitMagic = '魔法还在变，再等等它好吗？';
  static const byeBye = '再按一次返回，和小精灵说再见哦！';
  // 等待期轮播的小故事（设计 §2.3：TTS 持续陪伴）
  static const List<String> waitingStories = [
    '小精灵正在念咒语，咕噜咕噜变！',
    '魔法云朵正在打包你的动画，再等一小会儿！',
    '小精灵说：快好啦，快好啦！',
  ];
  // 线稿生成场景
  static const lineArtAsk = '说出你想画的小伙伴吧！';
  static const lineArtHit = '好的，来啦！'; // + 名字
  static const lineArtPainting = '小精灵正在画，等它一下下！';
  static const lineArtFallback = '小精灵没画出来，先给你一个好朋友涂吧！';
}
