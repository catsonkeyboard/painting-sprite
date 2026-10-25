# 动态施法（看图推荐愿望动作）设计文档

- 日期：2026-10-25
- 状态：待评审
- 前置：主设计文档 `docs/plans/2026-09-29-painting-sprite-design.md`（W3 魔法屏链路）

## 1. 背景与问题

当前魔法屏的 4 个愿望按钮（跳舞/飞起来/唱歌/奔跑）是硬编码的 `WishType`
枚举，对所有画作一视同仁。语义与图案错配：金鱼「飞起来」、火箭「奔跑」
出片违和；且固定按钮放弃了「App 看懂了孩子画的是什么」带来的惊喜感。

## 2. 目标

1. 进入魔法屏时，用多模态 LLM **识别画作主体**（小猫/金鱼/火箭…）；
2. 生成 **4 个贴合主体的施法动作**（小猫→奔跑/打滚/跳跃…，金鱼→游泳/吐泡泡…），
   每个动作含：中文标签、emoji、预生成的英文视频提示词、本地等待动画映射；
3. 愿望按钮**动态渲染**这 4 个动作，点击即施法（不再现场调 LLM）；
4. 语音许愿保持自由表达，但注入主体上下文提升出片质量。

### 非目标（本期不做）

- 本地等待动画扩充专属效果（游泳/升空仍映射现有 4 种变换，由 LLM 决定映射）
- 动作推荐的持久化缓存（同一画作重复进屏重复分析，实测嫌频繁再加哈希缓存）
- 家长配置页新增视觉模型字段（复用 ASR 模型字段；实测 lite 不支持图片再议）

## 3. 数据模型

新文件 `lib/magic/wish_action.dart`：

```dart
/// 一个可施法的愿望动作（数据驱动，替代固定枚举语义）。
class WishAction {
  final String label;    // 中文标签：游泳 / 升空 / 打滚
  final String emoji;    // 按钮图标：🏊 / 🚀（不得与麦克风 🎤 撞车）
  final String prompt;   // 预生成英文视频提示词（点击直用，≤500 字符）
  final WishType anim;   // 本地等待动画映射（dance/fly/sing/run 四选一）
}

/// 画作分析结果。
class ArtworkAnalysis {
  final String subject;           // 主体中文名：小猫（语音注入 + 相册愿望文本）
  final List<WishAction> actions; // 恰好 4 个

  /// 默认动作集（分析失败/未完成时的兜底按钮 = 现四愿望）。
  static const ArtworkAnalysis defaults = ...;
}
```

`WishType` 枚举保留，语义收窄为「本地动画类型」，不再直接对应按钮。

## 4. 服务层

### 4.1 AiService 接口新增

```dart
/// 画作分析：PNG → (主体, 4 个推荐动作)。
/// 返回 null = 失败/不支持（UI 落默认按钮；不造假数据）。
Future<ArtworkAnalysis?> analyzeArtwork(Uint8List pngBytes);
```

### 4.2 RealAiService

- 端点：`{doubaoBaseUrl}/chat/completions`（与 ASR 音频理解同族）
- 模型：`keys.doubaoAsrModel`（多模态豆包模型，一套 Key，不新增配置字段）
- 请求：`messages` 的 `content` 数组含 `text`（严格 JSON 输出指令）+
  `image_url`（`data:image/png;base64,...`）；`thinking: disabled`
- System prompt 要求输出：
  `{"subject":"小猫","actions":[{"label":"奔跑","emoji":"🏃","anim":"run","prompt":"..."},...恰好4个]}`
  并约束：动作贴合主体习性、prompt 英文儿童友好 ≤60 词、anim 只能取
  dance/fly/sing/run、emoji 不用 🎤
- 解析与校验（容错规则与 `_parseWishJson` 同模式）：
  - JSON 提取失败 / 字段缺失 / 空 label/emoji/prompt → 整体失败返回 null
  - 动作数 >4 取前 4，<4 → 整体失败返回 null（保持按钮数量恒定）
  - `anim` 越界 → 该动作丢弃；丢弃后不足 4 → 整体失败返回 null
  - `prompt` 超 500 字符截断；`emoji` 取首个字符（防 LLM 输出串）
- 超时 20 秒

### 4.3 FallbackAiService

- 真链路失败 → `degradedCount++` + 日志 + **返回 null**（沿用"降级不造假"原则，
  UI 用默认按钮兜底）；无 Key / 粘性降级期间 → 同样 null

### 4.4 MockAiService

- 立即返回通用默认分析：`subject: "小精灵"`，动作为现四愿望
  （跳舞🕺/飞起来🕊️/唱歌🎵/奔跑🏃）——离线/Mock 模式行为与现状完全一致

### 4.5 语音链路微调

`interpretWish(String text, {String? subject})`：
- system prompt 注入 `画的是一只${subject}`（subject 来自当次分析，可为 null）
- 分类白名单仍为 dance/fly/sing/run/other（本地动画映射所需）；
  video_prompt 生成时结合主体描述

## 5. 魔法屏 UI（MagicScreen）

### 5.1 状态与加载

```dart
ArtworkAnalysis? _analysis; // null = 未分析完成/失败
List<WishAction> get _actions =>
    _analysis?.actions ?? ArtworkAnalysis.defaults.actions;
```

- `initState`：`unawaited(_analyzeArtwork())`，**默认四按钮先渲染**（现状外观）
- 分析完成：`setState` 替换按钮（无感切换；可选轻弹跳动画，不做也罢）
- 分析期间点击默认按钮：照常施法（不等分析，孩子不等 LLM）

### 5.2 施法路径统一

- 点击动作按钮 `_castAction(WishAction a)`：
  - 本地演出 `_wish = a.anim`；视频提示词**直接用 `a.prompt`**（零 LLM 调用）
  - 存相册愿望文本：分析成功时 `${subject}${a.label}`（如「小猫游泳」），
    用默认动作时仅 `a.label`（如「奔跑」）
- 分析在施法进行中到达：只换按钮显示，不影响在途施法（施法捕获的是
  点击时的动作对象）
- 语音路径不变（ASR → interpretWish(subject) → 视频）
- `_castPreset`/`WishType.values` 按钮循环全部移除，改遍历 `_actions`
- 选中高亮：按被点击动作在列表中的索引比较

### 5.3 不变的行为

麦克风按住说话、施法中 PopScope 拦截 + TTS 劝等、等待计时、撒花复位、
视频下载落盘、配额扣退、二次许愿清理——全部维持现状。

## 6. 降级矩阵

| 场景 | 行为 |
|---|---|
| 无 Key / Mock 模式 | Mock 通用四动作（= 现状） |
| 视觉调用失败 / 返回垃圾 | 默认四按钮 + `[画作分析]` 日志 |
| 分析成功但某动作字段异常 | 丢弃该动作；不足 4 个则整体回默认 |
| lite 模型不支持图片输入（未实测风险） | 视觉调用 4xx → 回默认按钮；届时再议独立视觉模型字段 |
| 语音 interpretWish 失败 | 现状不变：默认提示词兜底 |

## 7. 成本与性能

- 每次进魔法屏 +1 次视觉调用：图片约 1-2k token + 输出约 300 token，
  doubao-seed-2-1-lite 档位下单次约几厘钱；延迟 1-3 秒（期间默认按钮可点）
- 施法点击路径反而**省一次 LLM 调用**（原来每次点击调 interpretWish）
- 不占云端许愿配额（analyzeArtwork 不是视频生成）

## 8. 测试计划

单元测试：
- 解析校验：正常 JSON、垃圾 JSON、动作数 5/3、anim 越界、空字段、超长 prompt
- Fallback：真链路失败返回 null（不造假）
- interpretWish subject 注入（MockClient 断言请求体含主体）

Widget 测试：
- 进屏默认四按钮渲染（现状用例继续过）
- Mock 分析结果到达后按钮替换（label/emoji 出现）
- 点击动态按钮 → 施法进入 casting（用 FakeSpeech + Mock AI）

## 9. 决策记录

| 决策 | 选择 | 理由 |
|---|---|---|
| 分析时机 | 进屏自动 | 按钮动态显示的前提；分析期默认按钮可点，孩子无感 |
| 点击是否再调 LLM | 否，用预生成 prompt | 零延迟；分析时已结合主体生成 |
| 语音是否限定推荐动作 | 否，自由表达 + 主体注入 | 保护表达欲（用户已拍板） |
| 视觉模型字段 | 暂不加，复用 ASR 字段 | 一套 Key 体验；lite 不支持图片再加（用户已拍板） |
| 本地动画 | 映射现有 4 种 | YAGNI；LLM 返回映射值 |
| 按钮数量 | 恒 4 | 布局稳定；触摸目标不缩水 |

## 10. 涉及文件

- 新增：`lib/magic/wish_action.dart`、`test/wish_action_test.dart`
- 修改：`lib/services/ai_service.dart`（接口 + Mock + 默认动作集）、
  `lib/services/real_ai_service.dart`（analyzeArtwork + interpretWish subject）、
  `lib/services/fallback_ai_service.dart`、`lib/screens/magic_screen.dart`（动态按钮 + _castAction）
- 不动：`lib/magic/magic_show.dart`（WishType 枚举与四种变换原样保留）
