# 动态施法（看图推荐愿望动作）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 进入魔法屏时用多模态 LLM 识别画作主体并动态生成 4 个贴合的施法动作按钮，点击即施法（零额外 LLM 调用）。

**Architecture:** 新增 `WishAction`/`ArtworkAnalysis` 数据模型；`AiService` 增加 `analyzeArtwork` 方法（Real 实现走 chat/completions 图像理解，Fallback 失败返回 null，Mock 返回默认动作）；魔法屏 initState 异步分析、按钮数据驱动渲染、点击用预生成提示词直连视频生成；语音路径注入主体上下文。

**Tech Stack:** Flutter/Dart、http、chat/completions `image_url` base64 输入（与 ASR `input_audio` 同族）。

**Spec:** `docs/plans/2026-10-25-dynamic-wish-actions-design.md`

## Global Constraints

- 模型复用 `keys.doubaoAsrModel`（多模态豆包），不新增配置字段（spec §9）
- `analyzeArtwork` 语义：HTTP/网络错误抛异常（与其他方法一致），内容解析失败返回 null；FallbackAiService 兜底后一律 null（降级不造假）
- 动作恒 4 个：解析后 >4 截前 4，丢弃校验失败的动作后不足 4 → 整体 null
- emoji 校验：非空、UTF-16 长度 ≤8、不得包含 `🎤`（与麦克风按钮冲突）
- prompt 截断 500 字符；`anim` 白名单 dance/fly/sing/run
- 本地动画 `WishType` 枚举与 `MagicShow` 四种变换**不改**
- 触摸目标 ≥64pt 不缩水；测试全绿 + analyze 零问题为每任务收尾
- 测试运行需 `export NO_PROXY=localhost,127.0.0.1,::1`（代理环境）

---

### Task 1: 数据模型 WishAction / ArtworkAnalysis

**Files:**
- Create: `lib/magic/wish_action.dart`
- Test: `test/wish_action_test.dart`

**Interfaces:**
- Consumes: `WishType`（来自 `lib/magic/magic_show.dart`，枚举值 dance/fly/sing/run，每个有 `label`/`emoji` 字段）
- Produces:
  - `class WishAction { const WishAction({required this.label, required this.emoji, required this.prompt, required this.anim}); final String label; final String emoji; final String prompt; final WishType anim; }`
  - `class ArtworkAnalysis { const ArtworkAnalysis({required this.subject, required this.actions}); final String subject; final List<WishAction> actions; static List<WishAction> get defaultActions => [...]; }`

- [ ] **Step 1: 写失败测试**

```dart
// test/wish_action_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:painting_sprite/magic/magic_show.dart';
import 'package:painting_sprite/magic/wish_action.dart';

void main() {
  test('默认动作集恰好 4 个，字段齐全且不与麦克风 emoji 冲突', () {
    final d = ArtworkAnalysis.defaultActions;
    expect(d.length, 4);
    for (final a in d) {
      expect(a.label, isNotEmpty);
      expect(a.emoji, isNotEmpty);
      expect(a.emoji.contains('🎤'), isFalse);
      expect(a.prompt, isNotEmpty);
      expect(WishType.values, contains(a.anim));
    }
  });

  test('默认动作集标签与原四愿望一致（向后兼容现有 UI）', () {
    final labels = ArtworkAnalysis.defaultActions.map((a) => a.label).toList();
    expect(labels, ['跳舞', '飞起来', '唱歌', '奔跑']);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd C:\Users\rogally\Documents\Code\painting-sprite && export NO_PROXY=localhost,127.0.0.1,::1 && flutter test test/wish_action_test.dart`
Expected: FAIL（`wish_action.dart` 不存在，编译错误）

- [ ] **Step 3: 最小实现**

```dart
// lib/magic/wish_action.dart
import 'package:painting_sprite/magic/magic_show.dart';

/// 一个可施法的愿望动作（数据驱动）。
///
/// 由 LLM 看图生成（[RealAiService.analyzeArtwork]），
/// 或降级时取 [ArtworkAnalysis.defaultActions]。
class WishAction {
  const WishAction({
    required this.label,
    required this.emoji,
    required this.prompt,
    required this.anim,
  });

  final String label; // 中文标签：游泳 / 升空
  final String emoji; // 按钮图标（不得为 🎤，与麦克风冲突）
  final String prompt; // 预生成英文视频提示词（点击直用）
  final WishType anim; // 本地等待动画映射（四选一）
}

/// 画作分析结果：主体 + 4 个推荐动作。
class ArtworkAnalysis {
  const ArtworkAnalysis({required this.subject, required this.actions});

  final String subject;
  final List<WishAction> actions;

  /// 默认动作集：分析失败/未完成时的兜底按钮（= 原固定四愿望）。
  static List<WishAction> get defaultActions => const [
        WishAction(
          label: '跳舞',
          emoji: '🕺',
          prompt: 'A cute doodle character dancing happily, vibrant colors, '
              'playful children animation style',
          anim: WishType.dance,
        ),
        WishAction(
          label: '飞起来',
          emoji: '🕊️',
          prompt: 'A cute doodle character flying in the blue sky with soft '
              'clouds, playful children animation style',
          anim: WishType.fly,
        ),
        WishAction(
          label: '唱歌',
          emoji: '🎵',
          prompt: 'A cute doodle character singing joyfully with colorful '
              'music notes, playful children animation style',
          anim: WishType.sing,
        ),
        WishAction(
          label: '奔跑',
          emoji: '🏃',
          prompt: 'A cute doodle character running happily across a bright '
              'meadow, playful children animation style',
          anim: WishType.run,
        ),
      ];
}
```

- [ ] **Step 4: 运行测试通过**

Run: `flutter test test/wish_action_test.dart`（同上目录与环境）
Expected: PASS（2 用例）

- [ ] **Step 5: 提交**

```bash
git add lib/magic/wish_action.dart test/wish_action_test.dart
git commit -m "feat: 动态施法数据模型 WishAction/ArtworkAnalysis"
```

---

### Task 2: AiService 接口 + Mock 实现

**Files:**
- Modify: `lib/services/ai_service.dart`
- Test: `test/wish_action_test.dart`（追加 group）

**Interfaces:**
- Consumes: Task 1 的 `ArtworkAnalysis`
- Produces: 抽象方法 `Future<ArtworkAnalysis?> analyzeArtwork(Uint8List pngBytes);`（所有实现类必须提供）；`MockAiService.analyzeArtwork` 返回 `(subject:'小精灵', defaultActions)`

- [ ] **Step 1: 追加失败测试**

```dart
// test/wish_action_test.dart 追加（import 增加 dart:typed_data 与 ai_service.dart）
  group('MockAiService.analyzeArtwork', () {
    test('返回通用默认动作集（离线可玩）', () async {
      final mock = MockAiService();
      final a = await mock.analyzeArtwork(Uint8List.fromList([1]));
      expect(a, isNotNull);
      expect(a!.subject, '小精灵');
      expect(a.actions.length, 4);
      expect(mock.callCount, 1);
    });
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/wish_action_test.dart`
Expected: FAIL（抽象类无 analyzeArtwork，编译错误）

- [ ] **Step 3: 实现**

`lib/services/ai_service.dart`：
```dart
// import 区追加：
import 'package:painting_sprite/magic/wish_action.dart';

// 抽象类 AiService 内追加（interpretWish 之后）：
  /// 画作分析：PNG → (主体, 4 个推荐动作)。
  /// 返回 null = 失败/不支持（UI 落默认按钮；不造假数据）。
  Future<ArtworkAnalysis?> analyzeArtwork(Uint8List pngBytes);
```
`MockAiService` 内追加：
```dart
  @override
  Future<ArtworkAnalysis?> analyzeArtwork(Uint8List pngBytes) async {
    callCount++;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return ArtworkAnalysis(subject: '小精灵', actions: ArtworkAnalysis.defaultActions);
  }
```

- [ ] **Step 4: 运行测试通过**（含 Task 1 用例不回归）

Run: `flutter test test/wish_action_test.dart`
Expected: PASS（3 用例）

- [ ] **Step 5: 提交**

```bash
git add lib/services/ai_service.dart test/wish_action_test.dart
git commit -m "feat: AiService.analyzeArtwork 接口 + Mock 实现"
```

---

### Task 3: RealAiService.analyzeArtwork（视觉调用 + 解析校验）

**Files:**
- Modify: `lib/services/real_ai_service.dart`
- Test: `test/wish_action_test.dart`（追加 group）

**Interfaces:**
- Consumes: Task 1 模型、`keys.doubaoAsrModel`、`keys.doubaoBaseUrl`、`AiHttpException`、既有 `_throwIfNotOk`
- Produces:
  - `Future<ArtworkAnalysis?> analyzeArtwork(Uint8List pngBytes)`（HTTP 错误抛 `AiHttpException`，内容不合法返回 null）
  - `static ArtworkAnalysis? parseAnalysis(String content)`（解析+校验，可单测）

- [ ] **Step 1: 追加失败测试**

```dart
// test/wish_action_test.dart 追加（import 增加 http/testing.dart、real_ai_service.dart、flutter/foundation.dart）
  group('RealAiService.parseAnalysis', () {
    const ok = '{"subject":"小猫","actions":['
        '{"label":"奔跑","emoji":"🏃","anim":"run","prompt":"a cat running"},'
        '{"label":"打滚","emoji":"🤸","anim":"dance","prompt":"a cat rolling"},'
        '{"label":"跳跃","emoji":"⬆️","anim":"fly","prompt":"a cat jumping"},'
        '{"label":"睡觉","emoji":"😴","anim":"sing","prompt":"a cat sleeping"}]}';

    test('正常 JSON 解析', () {
      final a = RealAiService.parseAnalysis(ok);
      expect(a!.subject, '小猫');
      expect(a.actions.length, 4);
      expect(a.actions.first.label, '奔跑');
      expect(a.actions.first.anim, WishType.run);
    });

    test('动作数 5 → 截前 4', () {
      final five = ok.replaceFirst(']}', ',{"label":"x","emoji":"✨","anim":"run","prompt":"p"}]}');
      expect(RealAiService.parseAnalysis(five)!.actions.length, 4);
    });

    test('动作数 3 / anim 越界丢弃后不足 4 / 垃圾 JSON / 空 prompt → null', () {
      const three = '{"subject":"猫","actions":['
          '{"label":"a","emoji":"✨","anim":"run","prompt":"p"},'
          '{"label":"b","emoji":"✨","anim":"run","prompt":"p"},'
          '{"label":"c","emoji":"✨","anim":"run","prompt":"p"}]}';
      expect(RealAiService.parseAnalysis(three), isNull);
      const badAnim = '{"subject":"猫","actions":['
          '{"label":"a","emoji":"✨","anim":"swim","prompt":"p"},'
          '{"label":"b","emoji":"✨","anim":"run","prompt":"p"},'
          '{"label":"c","emoji":"✨","anim":"run","prompt":"p"},'
          '{"label":"d","emoji":"✨","anim":"run","prompt":"p"}]}';
      expect(RealAiService.parseAnalysis(badAnim), isNull);
      expect(RealAiService.parseAnalysis('不是JSON'), isNull);
      const emptyPrompt = ok.replaceAll('"prompt":"a cat running"', '"prompt":" "');
      expect(RealAiService.parseAnalysis(emptyPrompt), isNull);
    });

    test('麦克风 emoji 的动作被丢弃（不足 4 → null）', () {
      const mic = ok.replaceFirst('"emoji":"🏃"', '"emoji":"🎤"');
      expect(RealAiService.parseAnalysis(mic), isNull);
    });

    test('超长 prompt 截断 500', () {
      final long = ok.replaceFirst(
          '"prompt":"a cat running"', '"prompt":"${'x' * 600}"');
      final a = RealAiService.parseAnalysis(long)!;
      expect(a.actions.first.prompt.length, 500);
    });
  });

  group('RealAiService.analyzeArtwork（HTTP 行为）', () {
    test('成功：请求含 image_url base64，返回解析结果', () async {
      String? body;
      final real = RealAiService(
        const AiKeys(doubaoApiKey: 'k', doubaoAsrModel: 'doubao-seed-2-1-lite-260915'),
        client: MockClient((req) async {
          body = req.body;
          return http.Response(
              '{"choices":[{"message":{"content":"$ok"}}]}', 200);
        }),
      );
      final a = await real.analyzeArtwork(Uint8List.fromList([1, 2]));
      expect(a!.subject, '小猫');
      expect(body, contains('image_url'));
      expect(body, contains('data:image/png;base64,'));
      expect(body, contains('doubao-seed-2-1-lite-260915'));
    });

    test('HTTP 500 → 抛 AiHttpException（由 Fallback 兜底）', () async {
      final real = RealAiService(
        const AiKeys(doubaoApiKey: 'k', doubaoAsrModel: 'doubao-seed-2-1-lite-260915'),
        client: MockClient((req) async => http.Response('boom', 500)),
      );
      await expectLater(
          real.analyzeArtwork(Uint8List.fromList([1])),
          throwsA(isA<AiHttpException>()));
    });
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/wish_action_test.dart`
Expected: FAIL（parseAnalysis 不存在，编译错误）

- [ ] **Step 3: 实现**

`lib/services/real_ai_service.dart`（import 区追加 `wish_action.dart` 与 `magic_show.dart`）：

```dart
  // ---------------- 画作分析（多模态视觉）----------------

  /// 画作 PNG → (主体, 4 个推荐动作)。
  ///
  /// 与 ASR 同一个多模态模型（一套 Key）；HTTP 错误抛 [AiHttpException]，
  /// 模型返回内容不合法返回 null（UI 落默认按钮）。
  Future<ArtworkAnalysis?> analyzeArtwork(Uint8List pngBytes) async {
    if (!keys.hasAsr) throw ApiKeyMissingError('画作分析');
    final resp = await _client.post(
      Uri.parse('${keys.doubaoBaseUrl}/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${keys.doubaoApiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': keys.doubaoAsrModel,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': '看这张儿童涂鸦。严格输出JSON（不要任何其他文字）：'
                    '{"subject":"<画的是什么，中文2-4字>",'
                    '"actions":[{"label":"<动作中文2-3字>","emoji":"<单个表情>",'
                    '"anim":"dance|fly|sing|run","prompt":"<英文视频提示词，'
                    '儿童友好、明快色彩、以画的主体为主语，不超过40词>"}]}。'
                    'actions 恰好 4 个，必须贴合所画主体的习性（如金鱼→游泳，'
                    '火箭→升空）；emoji 不要用 🎤；anim 是等待期动画类型：'
                    '摇摆类选 dance、飘浮/上升类选 fly、节奏/声音类选 sing、'
                    '移动类选 run。',
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/png;base64,${base64Encode(pngBytes)}',
                },
              },
            ],
          },
        ],
        'thinking': {'type': 'disabled'},
      }),
    ).timeout(const Duration(seconds: 20));
    _throwIfNotOk(resp, '画作分析');
    final content =
        jsonDecode(resp.body)['choices'][0]['message']['content'];
    if (content is! String) return null;
    return parseAnalysis(content);
  }

  /// 解析并校验模型输出；任何不合法 → null（降级不造假）。
  static ArtworkAnalysis? parseAnalysis(String content) {
    try {
      final m = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      final j = jsonDecode(m!.group(0)!) as Map<String, dynamic>;
      final subject = (j['subject'] as String?)?.trim();
      if (subject == null || subject.isEmpty) return null;
      final rawActions = j['actions'];
      if (rawActions is! List || rawActions.isEmpty) return null;

      final actions = <WishAction>[];
      for (final e in rawActions.take(4)) {
        if (e is! Map) continue;
        final label = (e['label'] as String?)?.trim() ?? '';
        var emoji = (e['emoji'] as String?)?.trim() ?? '';
        final prompt = ((e['prompt'] as String?) ?? '')
            .replaceAll(RegExp(r'[\r\n]+'), ' ')
            .trim();
        final animName = e['anim'] as String?;
        final anim = switch (animName) {
          'dance' => WishType.dance,
          'fly' => WishType.fly,
          'sing' => WishType.sing,
          'run' => WishType.run,
          _ => null,
        };
        // emoji 只保留第一个"表情单元"：截掉模型输出的多余文字
        if (emoji.length > 8) emoji = emoji.substring(0, 8);
        if (label.isEmpty || prompt.isEmpty || anim == null) continue;
        if (emoji.isEmpty || emoji.contains('🎤')) continue;
        actions.add(WishAction(
          label: label,
          emoji: emoji,
          prompt: prompt.length > 500 ? prompt.substring(0, 500) : prompt,
          anim: anim,
        ));
      }
      if (actions.length != 4) return null; // 恒 4 个，不足即整体失败
      return ArtworkAnalysis(subject: subject, actions: actions);
    } catch (_) {
      return null;
    }
  }
```

- [ ] **Step 4: 运行测试通过**

Run: `flutter test test/wish_action_test.dart`
Expected: PASS（全部用例）

- [ ] **Step 5: 提交**

```bash
git add lib/services/real_ai_service.dart test/wish_action_test.dart
git commit -m "feat: RealAiService.analyzeArtwork 视觉分析 + 解析校验"
```

---

### Task 4: FallbackAiService.analyzeArtwork + interpretWish subject 注入

**Files:**
- Modify: `lib/services/ai_service.dart`（抽象签名 + Mock 签名）
- Modify: `lib/services/real_ai_service.dart`（interpretWish）
- Modify: `lib/services/fallback_ai_service.dart`
- Test: `test/wish_action_test.dart`（追加 group）

**Interfaces:**
- Consumes: Task 3 的 `analyzeArtwork`
- Produces:
  - `AiService.interpretWish(String text, {String? subject})`（抽象与全部实现）
  - `FallbackAiService.analyzeArtwork`：真链路失败 → null + 日志
  - `RealAiService.interpretWish(String text, {String? subject})`：subject 注入 system prompt

- [ ] **Step 1: 追加失败测试**

```dart
// test/wish_action_test.dart 追加
  group('Fallback / interpretWish subject', () {
    test('analyzeArtwork 真链路失败 → null（不造假）+ 计数', () async {
      final real = RealAiService(
        const AiKeys(doubaoApiKey: 'k', doubaoAsrModel: 'doubao-seed-2-1-lite-260915'),
        client: MockClient((req) async => http.Response('boom', 500)),
      );
      final fb = FallbackAiService(real: real, mock: MockAiService());
      expect(await fb.analyzeArtwork(Uint8List.fromList([1])), isNull);
      expect(fb.degradedCount, 1);
    });

    test('interpretWish 注入主体到请求体', () async {
      String? body;
      final real = RealAiService(
        const AiKeys(doubaoApiKey: 'k', doubaoAsrModel: 'doubao-seed-2-1-lite-260915'),
        client: MockClient((req) async {
          body = req.body;
          return http.Response(
              '{"choices":[{"message":{"content":'
              '{"wish":"run","video_prompt":"a cat running"}"}}]}', 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );
      final r = await real.interpretWish('快跑', subject: '小猫');
      expect(r.wish, 'run');
      expect(body, contains('小猫'));
    });
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/wish_action_test.dart`
Expected: FAIL（subject 参数不存在，编译错误）

- [ ] **Step 3: 实现**

1) `lib/services/ai_service.dart` 抽象方法改为：
```dart
  Future<({String wish, String videoPrompt})> interpretWish(String text,
      {String? subject});
```
`MockAiService.interpretWish` 签名同步加 `{String? subject}`（实现忽略该参数）。

2) `lib/services/real_ai_service.dart` 的 `interpretWish` 签名与 system prompt 改为：
```dart
  Future<({String wish, String videoPrompt})> interpretWish(String text,
      {String? subject}) async {
    if (!keys.hasLlm) throw ApiKeyMissingError('LLM');
    final base = keys.llmBaseUrlEffective.replaceAll(RegExp(r'/+$'), '');
    final subjectHint =
        subject == null ? '' : '画作主体是「$subject」，视频提示词要以它为主语。';
```
messages 中 system 消息的 content 改为（原字符串仅在最前面插入 `$subjectHint`）：
```dart
            'content': '$subjectHint你是儿童涂鸦App的愿望精灵。孩子会说一句话描述想让'
                '自己的画做什么。请严格输出JSON：{"wish":"dance|fly|sing|run'
                '|other","video_prompt":"<英文视频提示词，儿童友好、'
                '明快色彩、描述主体动作，不超过60词>"}。不要输出任何其他文字。',
```
（方法其余部分——请求体结构、thinking disabled、超时、解析——原样保留。）
3) `lib/services/fallback_ai_service.dart`：
```dart
  @override
  Future<({String wish, String videoPrompt})> interpretWish(String text,
          {String? subject}) =>
      _interpretWish(text, subject);

  Future<({String wish, String videoPrompt})> _interpretWish(
      String text, String? subject) async {
    if (!_realConfigured || _sticky) return mock.interpretWish(text, subject: subject);
    try {
      final r = await real.interpretWish(text, subject: subject);
      _onRealSuccess();
      return r;
    } catch (e) {
      _onRealFailure('LLM', e);
      rethrow;
    }
  }

  @override
  Future<ArtworkAnalysis?> analyzeArtwork(Uint8List pngBytes) async {
    if (!_realConfigured || _sticky) return null;
    try {
      final r = await real.analyzeArtwork(pngBytes);
      if (r != null) _onRealSuccess();
      return r;
    } catch (e) {
      _onRealFailure('画作分析', e);
      return null; // UI 落默认按钮，不造假
    }
  }
```
（import 区追加 `wish_action.dart`）

- [ ] **Step 4: 运行测试通过**

Run: `flutter test test/wish_action_test.dart && flutter analyze | tail -1`
Expected: PASS + No issues

- [ ] **Step 5: 提交**

```bash
git add lib/services/ai_service.dart lib/services/real_ai_service.dart lib/services/fallback_ai_service.dart test/wish_action_test.dart
git commit -m "feat: Fallback.analyzeArtwork 兜底 + interpretWish 主体注入"
```

---

### Task 5: 魔法屏动态按钮 + 点击直用预生成提示词

**Files:**
- Modify: `lib/screens/magic_screen.dart`
- Test: `test/magic_dynamic_actions_test.dart`（新建）

**Interfaces:**
- Consumes: `ArtworkAnalysis.defaultActions`、`AiService.analyzeArtwork`、`interpretWish(text, subject:)`、`WishAction.anim/prompt/label/emoji`
- Produces: UI 行为（无新公共接口）

- [ ] **Step 1: 写失败测试**

```dart
// test/magic_dynamic_actions_test.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:painting_sprite/magic/magic_show.dart';
import 'package:painting_sprite/magic/wish_action.dart';
import 'package:painting_sprite/screens/magic_screen.dart';
import 'package:painting_sprite/services/ai_service.dart';
import 'package:painting_sprite/services/speech_service.dart';

/// 可编程 Mock：分析结果可注入。
class _FakeAi implements AiService {
  _FakeAi(this.analysis);
  final ArtworkAnalysis? analysis;
  int analyzeCalls = 0;
  String? lastVideoPrompt;

  @override
  Future<ArtworkAnalysis?> analyzeArtwork(Uint8List pngBytes) async {
    analyzeCalls++;
    return analysis;
  }

  @override
  Future<String> transcribe(Uint8List audioBytes) async => '跳舞';

  @override
  Future<List<Uint8List>> generateLineArt(String subject) async => [];

  @override
  Future<({String wish, String videoPrompt})> interpretWish(String text,
      {String? subject}) async {
    return (wish: 'dance', videoPrompt: 'llm prompt');
  }

  @override
  Future<Uri> animateDrawing({
    required Uint8List imageBytes,
    required String videoPrompt,
    bool Function()? isCancelled,
  }) async {
    lastVideoPrompt = videoPrompt;
    throw MockVideoDegraded(); // 直接落兜底，测试不依赖视频
  }

  @override
  Future<Uint8List?> downloadVideoOrNull(Uri url) async => null;
}

Widget _wrap(AiService ai) => MaterialApp(
      home: MagicScreen(
        pngBytes: Uint8List.fromList([1]),
        ai: ai,
        speech: FakeSpeechService(),
      ),
    );

void main() {
  testWidgets('进屏先渲染默认四按钮', (tester) async {
    final ai = _FakeAi(null); // 分析失败
    await tester.pumpWidget(_wrap(ai));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('🕺'), findsOneWidget);
    expect(find.text('🏃'), findsOneWidget);
    expect(ai.analyzeCalls, 1);
  });

  testWidgets('分析结果到达 → 按钮替换为动态动作', (tester) async {
    final ai = _FakeAi(const ArtworkAnalysis(subject: '金鱼', actions: [
      WishAction(label: '游泳', emoji: '🏊', prompt: 'a fish swimming', anim: WishType.fly),
      WishAction(label: '吐泡泡', emoji: '🫧', prompt: 'bubble', anim: WishType.sing),
      WishAction(label: '摇摆', emoji: '🐟', prompt: 'wiggle', anim: WishType.dance),
      WishAction(label: '冲刺', emoji: '💨', prompt: 'dash', anim: WishType.run),
    ]));
    await tester.pumpWidget(_wrap(ai));
    expect(find.text('🏊'), findsNothing); // 默认按钮先行
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('🏊'), findsOneWidget);
    expect(find.text('🏃'), findsNothing, reason: '默认按钮应被替换');
  });

  testWidgets('点击动态按钮 → 用预生成提示词施法（零 LLM）', (tester) async {
    final ai = _FakeAi(const ArtworkAnalysis(subject: '金鱼', actions: [
      WishAction(label: '游泳', emoji: '🏊', prompt: 'a fish swimming', anim: WishType.fly),
      WishAction(label: '吐泡泡', emoji: '🫧', prompt: 'bubble', anim: WishType.sing),
      WishAction(label: '摇摆', emoji: '🐟', prompt: 'wiggle', anim: WishType.dance),
      WishAction(label: '冲刺', emoji: '💨', prompt: 'dash', anim: WishType.run),
    ]));
    await tester.pumpWidget(_wrap(ai));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('🏊'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(ai.lastVideoPrompt, 'a fish swimming');
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/magic_dynamic_actions_test.dart`
Expected: FAIL（分析未触发/按钮仍为 WishType.values 固定循环）

- [ ] **Step 3: 实现 MagicScreen 改造**

`lib/screens/magic_screen.dart`：

1) import 追加 `wish_action.dart`。
2) State 字段追加：
```dart
  ArtworkAnalysis? _analysis; // null = 未完成/失败 → 默认按钮
  int? _activeActionIndex; // 当前施法动作高亮
```
3) `initState` 追加：
```dart
    unawaited(_analyzeArtwork());
```
4) 新增方法：
```dart
  /// 看图分析：成功换按钮，失败保默认（不阻塞、不打扰）。
  Future<void> _analyzeArtwork() async {
    try {
      final a = await widget.ai.analyzeArtwork(widget.pngBytes);
      if (a == null) {
        debugPrint('[画作分析] 未得到有效结果，保留默认按钮');
        return;
      }
      debugPrint('[画作分析] 主体=${a.subject} 动作=${a.actions.map((x) => x.label).join('/')}');
      if (mounted) setState(() => _analysis = a);
    } catch (e) {
      debugPrint('[画作分析] 失败，保留默认按钮：$e');
    }
  }
```
5) 删除 `_castPreset`，替换为：
```dart
  /// 动态动作按钮直通车：预生成提示词直用，点击零 LLM 调用。
  Future<void> _castAction(WishAction a, int index) async {
    if (busy) return;
    setState(() {
      _wish = a.anim;
      _activeActionIndex = index;
      _phase = _Phase.casting;
      _confetti = false;
    });
    final subject = _analysis?.subject;
    await _startMagicShow(
      a.label,
      presetPrompt: a.prompt,
      wishForStore: subject == null ? a.label : '$subject${a.label}',
    );
  }
```
6) `_startMagicShow` 签名与开头改为：
```dart
  Future<void> _startMagicShow(
    String wishText, {
    String? presetPrompt,
    String? wishForStore,
  }) async {
    ...
    var videoPrompt = presetPrompt ?? // 动作按钮：提示词已预生成，跳过 LLM
        'a cute doodle character dancing happily, playful children animation style';
    if (presetPrompt == null) {
      try {
        final r = await widget.ai.interpretWish(wishText,
            subject: _analysis?.subject);
        videoPrompt = r.videoPrompt;
        debugPrint('[LLM] 分类=${r.wish} 提示词="$videoPrompt"');
        if (mounted && seq == _castSeq) setState(() => _wish = _wishFromLabel(r.wish));
      } catch (e) {
        debugPrint('[LLM] 愿望理解失败，用默认提示词：$e');
      }
    }
```
方法内所有 `wishText` 传给 `ArtworkStore.save`/`_saveQuiet` 的位置改用 `wishForStore ?? wishText`（3 处 save + 1 处 _saveQuiet 调用参数）。
7) 按钮行 `for (final w in WishType.values)` 替换为：
```dart
        for (final (i, a) in _actions.indexed)
          KidUi.bigButton(
            size: KidUi.minTouch + 8,
            color: _activeActionIndex == i && _phase != _Phase.idle
                ? KidUi.magicPurple
                : Colors.white,
            onTap: busy ? () {} : () => _castAction(a, i),
            child: Text(a.emoji, style: const TextStyle(fontSize: 34)),
          ),
```
8) 新增 getter：
```dart
  List<WishAction> get _actions =>
      _analysis?.actions ?? ArtworkAnalysis.defaultActions;
```
9) 语音路径 `_castWithAudio` 里 `_startMagicShow(text)` 保持不变（无 presetPrompt → 走 LLM + 主体注入）。

- [ ] **Step 4: 运行全部测试**

Run: `flutter test && flutter analyze | tail -1`
Expected: 全部 PASS（含既有 widget_test 的 🕺🕊️🏃 断言——默认按钮标签/emoji 未变）+ No issues

- [ ] **Step 5: 提交**

```bash
git add lib/screens/magic_screen.dart test/magic_dynamic_actions_test.dart
git commit -m "feat: 魔法屏动态施法按钮（看图推荐 + 点击直用预生成提示词）"
```

---

### Task 6: 收尾——全量验证 + README 更新

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 全量验证**

Run: `cd C:\Users\rogally\Documents\Code\painting-sprite && export NO_PROXY=localhost,127.0.0.1,::1 && flutter analyze | tail -1 && flutter test 2>&1 | tail -1`
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 2: README 功能表更新**

魔法屏一行改为：
```
| ✨ 魔法屏 | 看图动态推荐 4 个施法动作（金鱼→游泳、火箭→升空…）；按住许愿（语音，注入主体上下文）→ 方舟 Seedance 图生视频（撒花庆祝）；等待期本地魔法演出（涂鸦扭动 + 粒子 + TTS） |
```
测试数量同步为最新用例数。

- [ ] **Step 3: 提交**

```bash
git add README.md
git commit -m "docs: README 动态施法功能说明"
```

- [ ] **Step 4: 构建 Windows 版供真机验证（可选，用户测试用）**

Run: `export PATH="$LOCALAPPDATA/Microsoft/WinGet/Links:$PATH" && flutter build windows --release`
Expected: 构建成功；用户测试看图推荐效果（金鱼/火箭画作各测一次）。
