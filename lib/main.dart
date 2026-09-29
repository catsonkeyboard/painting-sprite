import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:painting_sprite/screens/color_screen.dart';
import 'package:painting_sprite/screens/draw_screen.dart';
import 'package:painting_sprite/screens/magic_screen.dart';
import 'package:painting_sprite/services/ai_service.dart';
import 'package:painting_sprite/services/fallback_ai_service.dart';
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

  @override
  void initState() {
    super.initState();
    FallbackAiService.create().then((ai) {
      if (mounted) setState(() => _ai = ai);
    });
  }

  AiService get ai => _ai ?? MockAiService();

  void _goDraw() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DrawScreen(
          onDone: (png) => _toMagic(png),
        ),
      ),
    );
  }

  void _goColor() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ColorScreen(
          ai: ai,
          onDone: (png) => _toMagic(png),
        ),
      ),
    );
  }

  void _toMagic(Uint8List bytes) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MagicScreen(
          pngBytes: bytes,
          ai: ai,
          speech: _speech,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 1),
            Text(
              '🖌️ 涂鸦精灵',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF5D4037),
                shadows: [
                  Shadow(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.35),
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
                  emoji: '✨',
                  bg: const Color(0xFFFFAB91),
                  onTap: _goColor, // 线稿涂色入口（语音线稿 + 内置库）
                ),
              ],
            ),
            const Spacer(flex: 2),
          ],
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
