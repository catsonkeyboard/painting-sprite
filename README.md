# 🖌️ 涂鸦精灵（painting-sprite）

给 3-6 岁孩子的魔法涂鸦 App：**画出来的东西，许个愿就活过来。**

孩子自由涂鸦（或在语音生成的线稿上涂色），按住麦克风说出愿望——"让它跳起舞来！"——涂鸦就变成一段 5 秒的动画。全程零文字 UI，语音引导贯穿始终；断网、没配密钥也照常可玩（本地魔法动画兜底）。

> 个人项目 · Flutter 单码库 · 主力平台：Android 平板（arm64）
> 设计文档：[docs/plans/2026-09-29-painting-sprite-design.md](docs/plans/2026-09-29-painting-sprite-design.md)

## ✨ 功能全景

| 模块 | 能力 |
|---|---|
| 🖌️ 画画屏 | 大画笔（3 档粗细）、10 色大色盘、橡皮、撤销/重做、PNG 导出 |
| 🎨 涂色屏 | 内置 8 张线稿；按住说话生成线稿（ASR → 命中内置库秒出 / 未命中走云端生成二选一）；泛洪填色（黑线永不被涂掉、容差吃灰边） |
| ✨ 魔法屏 | 按住许愿（语音）或 4 个预设愿望按钮 → 可灵图生视频（撒花庆祝）；等待期本地魔法演出（涂鸦扭动 + 粒子 + TTS） |
| 🖼️ 相册 | 作品缩略图网格、动画播放（本地/URL）、愿望文本持久化、删除 |
| ⚙️ 家长设置 | 两位数加法门（儿童止步）+ 每日云端许愿限额（失败自动退还） |
| 🛡️ 四级降级 | 录音太短→重说；ASR/LLM 失败→自动降级；视频失败→本地动画兜底；无密钥→全 Mock 模式 |

儿童设计细节：全部触摸目标 ≥64pt、零文字依赖（TTS 语音引导 + emoji 图标）、按钮圆滚滚糖果色。

## 🚀 快速开始

```bash
flutter pub get
flutter run    # 连接设备中选择（Android 平板优先）

# 只编 arm64 release 包（24.6MB）
flutter build apk --release --target-platform android-arm64 --split-per-abi
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

测试（代理环境下本地 WebSocket 需要 NO_PROXY）：

```bash
flutter test        # 12 个用例全绿
flutter analyze     # 零问题
```

## 🔑 AI 密钥配置（可选）

不配置 = Mock 模式，全功能可玩（视频走本地动画兜底）。配置后解锁真链路：

```bash
cp ai_keys.example.json assets/ai_keys.json   # Android：打包进 App
# 或放项目根 ai_keys.json                      # 桌面调试
```

```jsonc
{
  "doubao_api_key": "…",          // 火山方舟：ASR + Seedream 线稿
  "llm_api_key": "…",             // 任意 OpenAI 兼容 chat completions
  "llm_base_url": "https://api.deepseek.com/v1",
  "llm_model": "deepseek-chat",
  "kling_access_key": "…",        // 可灵开放平台：图生视频
  "kling_secret_key": "…"
}
```

LLM 端点完全可插拔：智谱 GLM（免费档）/ DeepSeek / Qwen / 本地 Ollama 均可。密钥文件已 gitignore，绝不入库。

## 📐 项目结构

```
lib/
├── main.dart                      # 入口 + 首页四入口（画画/涂色/相册/设置）
├── models/stroke.dart             # 笔画模型
├── painting/                      # 画板引擎
│   ├── canvas_controller.dart     #   笔画数据 + 撤销/重做栈
│   ├── doodle_canvas.dart         #   手绘画布 + RepaintBoundary PNG 导出
│   ├── doodle_painter.dart        #   CustomPainter
│   └── pen_config.dart            #   画笔配置（颜色/粗细/橡皮）
├── coloring/flood_filler.dart     # 泛洪填色引擎（span-scanline + YIQ 亮度保持）
├── magic/magic_show.dart          # 本地魔法动画（4 种愿望）+ 粒子 + 撒花
├── screens/                       # 四屏 + 相册 + 家长设置
│   ├── draw_screen.dart           #   ① 画画屏
│   ├── color_screen.dart          #   ② 涂色屏（线稿库/语音生成/二选一）
│   ├── magic_screen.dart          #   ③ 魔法屏（许愿→视频/兜底状态机）
│   ├── gallery_screen.dart        #   相册
│   └── settings_screen.dart       #   家长设置（算术门+限额）
├── services/                      # 全部可插拔
│   ├── ai_service.dart            #   AiService 抽象 + MockAiService
│   ├── real_ai_service.dart       #   豆包ASR/GLM/Seedream/可灵（JWT自签名+轮询）
│   ├── fallback_ai_service.dart   #   降级网关（真→Mock 自动切换）
│   ├── ai_keys.dart               #   密钥加载（assets 优先/桌面回退）
│   ├── speech_service.dart        #   TTS 抽象 + 童趣话术库
│   ├── system_speech_service.dart #   flutter_tts 实现（懒加载容错）
│   ├── hold_to_talk.dart          #   按住录音（m4a/16k 单声道）
│   ├── artwork_store.dart         #   本地相册（png+mp4+wishes.json）
│   └── wish_quota.dart            #   每日云端配额（跨天清零/失败退还）
└── ui/kid_ui.dart                 # 儿童触摸目标 + 糖果色主题
```

## 🗺️ 路线图

| 阶段 | 内容 | 状态 |
|---|---|---|
| W1 | 画板 + 本地动画 + 三屏骨架 | ✅ |
| W2 | 线稿库 + 泛洪涂色 + AI 服务抽象 | ✅ |
| W3 | 语音许愿全链路 + 四级降级 | ✅ |
| W4 | 撒花 + 相册 + 家长限流 | ✅ |
| 加餐 | 语音线稿二选一 + TTS 全接线 + arm64 release | ✅ |
| 待办 | 平板真机联调 + 真密钥校准 | ⬜ |

## 🐛 已知平台坑

- macOS 构建遇 `sandbox-exec: sandbox_apply: Operation not permitted` → Flutter 3.47 的 SPM 集成问题，`flutter config --no-enable-swift-package-manager` 或按官方指引移除工程 SPM 引用
- 代理环境跑测试需 `NO_PROXY=localhost,127.0.0.1,::1`（否则本地 WebSocket 被劫持）
- 代码中 LLM/ASR/视频的模型名以 `ai_keys.example.json` 默认值为准，与控制台开通的模型不一致时在配置中覆盖

## 📄 License

[MIT](LICENSE) © 2026 catsonkeyboard
