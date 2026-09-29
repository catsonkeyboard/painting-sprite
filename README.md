# 🖌️ 涂鸦精灵（painting-sprite）

给 3-6 岁孩子的魔法涂鸦 App：画出来的东西，许个愿就活过来。

> 家庭项目 · Flutter 四端单码库（iOS / Android / macOS / Windows）
> 设计文档：[docs/plans/2026-09-29-painting-sprite-design.md](docs/plans/2026-09-29-painting-sprite-design.md)

## 当前状态（W1-W4 全部完成，Android 平板为主力平台）

- ✅ 屏① 画画屏：大画笔（3 档粗细）、10 色大色盘、橡皮、撤销、清空、PNG 导出
- ✅ 屏② 涂色屏：内置 8 张线稿 + 语音线稿（真录音→ASR→Seedream 二选一）+ 泛洪填色
- ✅ 屏③ 魔法屏：按住许愿（语音/预设按钮）→ 可灵视频（撒花庆祝）+ 本地动画兜底
- ✅ 作品相册（缩略图/详情播放/删除）+ 家长设置（算术题门 + 每日云端限额）
- ✅ 四级降级：全链路无密钥也照常可玩（Mock 模式）
- ✅ TTS 语音引导全覆盖（启动欢迎/各屏引导/魔法话术）

## 快速开始

```bash
# 本机 Flutter 在 ~/development/flutter（不在 PATH）
flutter run                       # 连接的设备中选择（Android 平板优先）
flutter build apk --release --split-per-abi  # release 分架构 APK
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

**AI 密钥配置**（可选，不配 = Mock 模式）：复制 `ai_keys.example.json` 为 `assets/ai_keys.json`（Android 打包进 App）或项目根 `ai_keys.json`（桌面），填入 doubao/llm/kling 密钥。LLM 支持任意 OpenAI 兼容端点（GLM/DeepSeek/Ollama 均可）。

跑测试 / 构建时带上（Clash 代理会劫持本地 WebSocket）：

```bash
NO_PROXY=localhost,127.0.0.1,::1 flutter test
```

## 项目结构

```
lib/
├── main.dart                  # 入口 + 首页三入口
├── models/stroke.dart         # 笔画模型
├── painting/                  # 画板引擎
│   ├── canvas_controller.dart # 笔画数据 + 撤销/重做
│   ├── doodle_canvas.dart     # 手绘画布 + PNG 导出
│   ├── doodle_painter.dart    # CustomPainter
│   └── pen_config.dart        # 画笔配置
├── magic/magic_show.dart      # 本地魔法动画 + 粒子（等待期演出/兜底）
├── screens/                   # 三屏
│   ├── draw_screen.dart       # ① 画画屏
│   ├── color_screen.dart      # ② 涂色屏（W2 完整版）
│   └── magic_screen.dart      # ③ 魔法屏（W3 接云端视频）
├── services/speech_service.dart # TTS 抽象 + 童趣话术库
└── ui/kid_ui.dart             # 儿童超大触摸目标 + 糖果色系
```

## 路线图

| 周 | 内容 | 状态 |
|---|---|---|
| W1 | 画板 + 本地动画 + 三屏骨架 | ✅ 完成 |
| W2 | 语音生成线稿 + 泛洪涂色 + 内置线稿库 + TTS | ✅ 完成 |
| W3 | 语音许愿全链路（ASR→LLM→可灵视频）+ 降级阶梯 | ✅ 完成 |
| W4 | 魔法演出打磨 + 相册 + 家长限流 | ✅ 完成 |
| 加餐 | 语音线稿真链路二选一 + TTS 全接线 + release 瘦身 | ✅ 完成 |
| 待办 | 真机联调（平板到手）+ 真密钥校准 | ⬜ |

## 已知平台坑（这台机器）

- `flutter create` 会卡在证书选择，需管道喂 `printf '1\n'`（选 leemeany@outlook.com 证书）
- Flutter 3.47 的 Swift Package Manager 集成与 xcodebuild sandbox 冲突（`sandbox-exec: sandbox_apply: Operation not permitted`），已按官方指引从 macos/Runner.xcodeproj 移除 SPM 引用（项目零原生插件时无副作用）
- Bash 里 grep/sed 是 toybox shim，行为怪异；用 Grep 工具或 `/usr/bin/sed`
