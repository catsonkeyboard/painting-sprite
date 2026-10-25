import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:painting_sprite/services/ai_keys.dart';
import 'package:painting_sprite/services/wish_quota.dart';
import 'package:painting_sprite/ui/kid_ui.dart';

/// 家长设置屏：算术题门（学龄前儿童挡在门外）+ 每日许愿限额
/// + 模型/密钥配置（应用内热生效，无需重新打包）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onAiConfigChanged});

  /// 应用内模型配置保存/清除后回调（重建 AI 服务实例）。
  final Future<void> Function()? onAiConfigChanged;

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

  // 连续答错冷却：学龄前儿童瞎蒙几十次也可能撞对，加个 30 秒冷静期
  int _fails = 0;
  DateTime? _lockUntil;
  static const int _lockAfterFails = 3;
  static const Duration _lockDuration = Duration(seconds: 30);

  bool get _locked => _lockUntil != null && DateTime.now().isBefore(_lockUntil!);

  // ---- 模型配置表单 ----
  final _doubaoKey = TextEditingController();
  final _doubaoAsrModel = TextEditingController();
  final _doubaoImageModel = TextEditingController();
  final _doubaoVideoModel = TextEditingController();
  final _doubaoBaseUrl = TextEditingController();
  final _llmKey = TextEditingController();
  final _llmBaseUrl = TextEditingController();
  final _llmModel = TextEditingController();

  late final List<TextEditingController> _allControllers = [
    _doubaoKey, _doubaoAsrModel, _doubaoImageModel, _doubaoVideoModel, _doubaoBaseUrl,
    _llmKey, _llmBaseUrl, _llmModel,
  ];

  bool _keysLoaded = false;
  bool _showSecrets = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _newQuestion();
    _loadStatus();
    _loadKeys();
    // 输入即刷新状态徽章
    for (final c in _allControllers) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final c in _allControllers) {
      c.dispose();
    }
    super.dispose();
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

  /// 回填当前生效配置（应用内 > assets > 根目录文件）。
  Future<void> _loadKeys() async {
    final keys = await AiKeys.load();
    if (!mounted) return;
    setState(() {
      _doubaoKey.text = keys.doubaoApiKey ?? '';
      _doubaoAsrModel.text = keys.doubaoAsrModel;
      _doubaoImageModel.text = keys.doubaoImageModel;
      _doubaoVideoModel.text = keys.doubaoVideoModel;
      _doubaoBaseUrl.text = keys.doubaoBaseUrl;
      _llmKey.text = keys.llmApiKey ?? '';
      _llmBaseUrl.text = keys.llmBaseUrl;
      _llmModel.text = keys.llmModel;
      _keysLoaded = true;
    });
  }

  // ---- 表单实时状态（与 AiKeys 的判定规则保持一致）----

  String get _asrStatus {
    final keySet = _doubaoKey.text.trim().isNotEmpty;
    final m = _doubaoAsrModel.text.trim();
    if (keySet && m.isNotEmpty && m != AiKeys.asrModelPlaceholder) return '真链路';
    if (keySet) return '半配置'; // 密钥在但模型还是占位/空
    return 'Mock';
  }

  String get _imageStatus =>
      _doubaoKey.text.trim().isNotEmpty ? '真链路' : 'Mock';

  String get _videoStatus =>
      _doubaoKey.text.trim().isNotEmpty ? '真链路' : 'Mock';

  /// LLM：独立 Key 或 豆包 Key 回落（llm Key 留空且 base 未指向他厂）。
  String get _llmStatus {
    if (_llmKey.text.trim().isNotEmpty) return '真链路';
    final doubaoSet = _doubaoKey.text.trim().isNotEmpty;
    final b = _llmBaseUrl.text.trim();
    return (doubaoSet && (b.isEmpty || b.contains('volces.com'))) ? '真链路' : 'Mock';
  }

  Future<void> _saveConfig() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final keys = AiKeys.fromJson(jsonEncode(<String, dynamic>{
        'doubao_api_key': _doubaoKey.text.trim(),
        'doubao_asr_model': _doubaoAsrModel.text.trim(),
        'doubao_image_model': _nz(_doubaoImageModel),
        'doubao_video_model': _nz(_doubaoVideoModel),
        'doubao_base_url': _nz(_doubaoBaseUrl),
        'llm_api_key': _llmKey.text.trim(),
        'llm_base_url': _llmBaseUrl.text.trim(),
        'llm_model': _llmModel.text.trim(),
      }));
      await AiKeys.saveAppOverride(keys);
      await widget.onAiConfigChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存，AI 服务已重新加载（已打开的画画/魔法屏需重新进入才生效）')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearOverride() async {
    await AiKeys.clearAppOverride();
    await _loadKeys(); // 回填回落后的文件配置
    await widget.onAiConfigChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清除应用内配置，回落到 assets/根目录文件配置')),
      );
    }
  }

  /// 空值返回 null（让 fromJson 套用默认值，避免把空串写死成配置）。
  String? _nz(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  void _tryUnlock() {
    final (a, b) = _question!;
    final ans = int.tryParse(_controller.text.trim());
    if (ans == a + b) {
      setState(() {
        _unlocked = true;
        _fails = 0;
        _lockUntil = null;
      });
    } else {
      _fails++;
      final locked = _fails >= _lockAfterFails;
      setState(() {
        _error = locked ? '休息 30 秒再试~' : '再试试~';
        _controller.clear();
        _newQuestion();
        if (locked) {
          _fails = 0;
          _lockUntil = DateTime.now().add(_lockDuration);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚙️ 家长设置'),
        backgroundColor: KidUi.bgCream,
        foregroundColor: KidUi.textBrown,
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
              onPressed: _locked ? null : _tryUnlock,
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
        _buildQuotaCard(),
        const SizedBox(height: 12),
        _buildStatusCard(),
        const SizedBox(height: 12),
        _buildConfigCard(),
      ],
    );
  }

  Widget _buildQuotaCard() {
    return Card(
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
                style: TextStyle(color: KidUi.textBrownLight)),
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
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI 真链路状态', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(label: '🎤 语音识别', status: _asrStatus),
                _StatusChip(label: '🎨 线稿生成', status: _imageStatus),
                _StatusChip(label: '🧠 愿望理解', status: _llmStatus),
                _StatusChip(label: '🎬 视频生成', status: _videoStatus),
              ],
            ),
            if (_asrStatus == '半配置')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ ASR 密钥已填但模型名仍是占位值，语音识别走 Mock。'
                  '请填入方舟控制台实际开通的模型/接入点 ID（常见形如 ep-xxxx）。',
                  style: TextStyle(color: KidUi.textBrownLight),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigCard() {
    if (!_keysLoaded) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('模型与密钥配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: _showSecrets ? '隐藏密钥' : '显示密钥',
                  icon: Icon(_showSecrets ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showSecrets = !_showSecrets),
                ),
              ],
            ),
            const Text(
              '保存在应用内（优先级最高），改密钥/模型无需重新打包。\n'
              '优先级：应用内 > assets/ai_keys.json > 根目录 ai_keys.json。',
              style: TextStyle(color: KidUi.textBrownLight),
            ),
            const SizedBox(height: 8),
            Theme(
              // 去掉 ExpansionTile 自带分割线，跟卡片风格统一
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: Column(
                children: [
                  ExpansionTile(
                    title: const Text('🎤 语音识别 + 🎨 线稿 + 🎬 视频（火山方舟）'),
                    subtitle: const Text('一个 API Key 通吃三个能力'),
                    children: [
                      _field('API Key（doubao_api_key）', _doubaoKey, secret: true),
                      _field(
                        'ASR 模型（doubao_asr_model）',
                        _doubaoAsrModel,
                        hint: '语音识别走方舟音频理解：填支持音频输入的多模态'
                            '豆包模型（默认 doubao-seed-2-1-lite）',
                      ),
                      _field('图像模型（doubao_image_model）', _doubaoImageModel,
                          hint: 'Seedream 线稿生成。默认 5.0 flash（性价比）；'
                              '线条闭合率要求高可换 pro 档（控制台确切 ID 为准）'),
                      _field('视频模型（doubao_video_model）', _doubaoVideoModel,
                          hint: 'Seedance 图生视频。默认 2.0 mini（性价比）；'
                              '要更强可换 Doubao-Seedance-2.0 / 2.5（确切模型 ID 见控制台详情页）'),
                      _field('Base URL（doubao_base_url）', _doubaoBaseUrl),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('🧠 愿望理解（LLM，OpenAI 兼容）'),
                    subtitle: const Text('Key 留空 = 复用豆包 Key（豆包模型）；或指向智谱/DeepSeek/Ollama'),
                    children: [
                      _field('API Key（llm_api_key）', _llmKey, secret: true, fieldKey: const Key('llm_api_key_field')),
                      _field('Base URL（llm_base_url）', _llmBaseUrl, hint: '留空自动跟随：豆包 Key → 方舟；否则默认智谱'),
                      _field('模型（llm_model）', _llmModel, hint: '留空自动跟随：豆包 Key → doubao-seed-2-1-lite；否则 glm-4-flash'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: _saving ? null : _saveConfig,
                  child: _saving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _clearOverride,
                  child: const Text('清除应用内配置'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {bool secret = false, String? hint, Key? fieldKey}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: fieldKey,
        controller: c,
        obscureText: secret && !_showSecrets,
        autofillHints: secret ? null : const [AutofillHints.url],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.status});

  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      '真链路' => (Colors.green, '✅'),
      '半配置' => (Colors.orange, '⚠️'),
      _ => (Colors.grey, '💤'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 4),
          Text('$icon $status', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
