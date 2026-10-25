import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:painting_sprite/screens/color_screen.dart';
import 'package:painting_sprite/screens/draw_screen.dart';
import 'package:painting_sprite/screens/gallery_screen.dart';
import 'package:painting_sprite/screens/magic_screen.dart';
import 'package:painting_sprite/screens/settings_screen.dart';
import 'package:painting_sprite/services/ai_service.dart';
import 'package:painting_sprite/services/fallback_ai_service.dart';
import 'package:painting_sprite/services/speech_service.dart';
import 'package:painting_sprite/services/system_speech_service.dart';
import 'package:painting_sprite/ui/kid_ui.dart';

void main() {
  runApp(const PaintingSpriteApp());
}

class PaintingSpriteApp extends StatelessWidget {
  const PaintingSpriteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '涂鸦精灵',
      debugShowCheckedModeBanner: false,
      theme: KidUi.theme(),
      home: const HomeScreen(),
    );
  }
}

/// 首页：三个大入口（零文字依赖——大图标 + TTS 引导）。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // W3：真 TTS + 真假自动切换的 AI 网关（无 ai_keys.json 时全自动 Mock）
  final _speech = SystemSpeechService();
  AiService? _ai;

  // FallbackAiService 就绪前的 Mock 兜底：固定实例，
  // 避免每次 getter 新建（callCount 等状态互相独立）。
  final MockAiService _mockAi = MockAiService();

  /// 两次返回退出的窗口起点（儿童 App 惯例：防误触退出）。
  DateTime? _lastBackAt;

  @override
  void initState() {
    super.initState();
    _speech.speak(MagicPhrases.welcome); // 启动欢迎语
    FallbackAiService.create().then((ai) {
      if (mounted) setState(() => _ai = ai);
    });
  }

  AiService get ai => _ai ?? _mockAi;

  void _goDraw() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DrawScreen(
          speech: _speech,
          onDone: (png) => _toMagic(png, null), // 自由涂鸦：主体未知，走看图分析
        ),
      ),
    );
  }

  void _goColor() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ColorScreen(
          ai: ai,
          speech: _speech,
          // 内置线稿带已知主体 → 魔法屏直接用预制动作集
          onDone: (png, knownSubject) => _toMagic(png, knownSubject),
        ),
      ),
    );
  }

  void _goGallery() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GalleryScreen()),
    );
  }

  void _goSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(onAiConfigChanged: _reloadAi),
      ),
    );
  }

  /// 应用内模型配置变更后重建 AI 服务（新进入的画画/涂色/魔法屏用新配置）。
  Future<void> _reloadAi() async {
    final ai = await FallbackAiService.create();
    if (mounted) setState(() => _ai = ai);
  }

  void _toMagic(Uint8List bytes, String? knownSubject) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MagicScreen(
          pngBytes: bytes,
          ai: ai,
          speech: _speech,
          knownSubject: knownSubject,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 两次返回退出：第一次只播 TTS 提示，2 秒内再按才真正退出
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackAt != null &&
            now.difference(_lastBackAt!) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        _lastBackAt = now;
        _speech.speak(MagicPhrases.byeBye);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 1),
              Text(
                '🖌️ 涂鸦精灵',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: KidUi.textBrown,
                  shadows: [
                    Shadow(
                      color: KidUi.magicPurple.withValues(alpha: 0.35),
                      offset: const Offset(0, 4),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _BigEntry(
                    emoji: '🖌️',
                    bg: const Color(0xFFFFD54F),
                    onTap: _goDraw,
                  ),
                  _BigEntry(
                    emoji: '🎨',
                    bg: const Color(0xFF81D4FA),
                    onTap: _goColor,
                  ),
                  _BigEntry(
                    emoji: '🖼️',
                    bg: const Color(0xFFFFAB91),
                    onTap: _goGallery,
                  ),
                  _BigEntry(
                    emoji: '⚙️',
                    bg: const Color(0xFFCEDBD2),
                    onTap: _goSettings,
                  ),
                ],
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigEntry extends StatelessWidget {
  const _BigEntry({required this.emoji, required this.bg, required this.onTap});

  final String emoji;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white, width: 6),
          boxShadow: [
            BoxShadow(
              color: bg.withValues(alpha: 0.5),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 48))),
      ),
    );
  }
}
