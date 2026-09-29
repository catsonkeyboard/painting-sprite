import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:painting_sprite/services/wish_quota.dart';

/// 家长设置屏：算术题门（学龄前儿童挡在门外）+ 每日许愿限额。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _unlocked = false;
  (int, int)? _question; // (a, b)
  final _controller = TextEditingController();
  String? _error;

  int _limit = WishQuota.defaultLimit;
  int _used = 0;

  @override
  void initState() {
    super.initState();
    _newQuestion();
    _loadStatus();
  }

  void _newQuestion() {
    final r = Random();
    _question = (r.nextInt(20) + 11, r.nextInt(20) + 11); // 两位数加法
  }

  Future<void> _loadStatus() async {
    final s = await WishQuota.status();
    if (mounted) {
      setState(() {
        _used = s.$1;
        _limit = s.$2;
      });
    }
  }

  void _tryUnlock() {
    final (a, b) = _question!;
    final ans = int.tryParse(_controller.text.trim());
    if (ans == a + b) {
      setState(() => _unlocked = true);
    } else {
      setState(() {
        _error = '再试试~';
        _controller.clear();
        _newQuestion();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚙️ 家长设置'),
        backgroundColor: const Color(0xFFFFF8E7),
        foregroundColor: const Color(0xFF5D4037),
      ),
      body: _unlocked ? _buildSettings() : _buildGate(),
    );
  }

  Widget _buildGate() {
    final (a, b) = _question!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔐 家长验证', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('$a + $b = ?', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24),
                decoration: InputDecoration(
                  hintText: '答案',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _tryUnlock(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _tryUnlock,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text('解锁', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今日云端许愿：$_used / $_limit 次',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('超出限额后，孩子仍可用预设按钮（本地动画，零成本）。',
                    style: TextStyle(color: Color(0xFF8D6E63))),
                const SizedBox(height: 16),
                const Text('每日限额', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final n in const [3, 5, 10, 20, 9999])
                      ChoiceChip(
                        label: Text(n == 9999 ? '不限' : '$n 次'),
                        selected: _limit == n,
                        onSelected: (_) {
                          WishQuota.setLimit(n).then((_) => _loadStatus());
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('密钥配置', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'AI 密钥在 assets/ai_keys.json（Android 打包进 App）或项目根 '
                  'ai_keys.json（桌面）。未配置时全链路自动 Mock，本地模式可玩。\n'
                  '模板见 ai_keys.example.json。',
                  style: TextStyle(color: Color(0xFF8D6E63)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
