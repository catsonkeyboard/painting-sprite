# 🖌️ 涂鸦精灵（painting-sprite）

给 3-6 岁孩子的魔法涂鸦 App：画出来的东西，许个愿就活过来。

> 家庭项目 · Flutter 四端单码库（iOS / Android / macOS / Windows）
> 设计文档：[docs/plans/2026-09-29-painting-sprite-design.md](docs/plans/2026-09-29-painting-sprite-design.md)

## 当前状态（W1 已完成）

- ✅ 四端工程骨架 + 应用名"涂鸦精灵"
- ✅ 屏① 画画屏：大画笔（3 档粗细）、10 色大色盘、橡皮、撤销、清空、PNG 导出
- ✅ 屏② 涂色屏骨架（W2 接语音线稿 + 泛洪涂色）
- ✅ 屏③ 魔法屏：作品预览 + 4 种本地魔法动画（跳舞/飞/唱歌/奔跑）+ 施法粒子特效
- ✅ 测试 7/7 通过，flutter analyze 零问题，macOS 构建成功

## 快速开始

```bash
# 本机 Flutter 在 ~/development/flutter（不在 PATH）
flutter run -d macos        # macOS 桌面
flutter run -d <ios-device> # iPad / iPhone
flutter run                 # 连接的设备中选择
```

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
| W2 | 语音生成线稿 + 泛洪涂色 + 内置线稿库 + TTS | ⬜ |
| W3 | 语音许愿全链路（ASR→LLM→可灵视频）+ 降级阶梯 | ⬜ |
| W4 | 魔法演出打磨 + 四端验收 + 限流开关 | ⬜ |

## 已知平台坑（这台机器）

- `flutter create` 会卡在证书选择，需管道喂 `printf '1\n'`（选 leemeany@outlook.com 证书）
- Flutter 3.47 的 Swift Package Manager 集成与 xcodebuild sandbox 冲突（`sandbox-exec: sandbox_apply: Operation not permitted`），已按官方指引从 macos/Runner.xcodeproj 移除 SPM 引用（项目零原生插件时无副作用）
- Bash 里 grep/sed 是 toybox shim，行为怪异；用 Grep 工具或 `/usr/bin/sed`
