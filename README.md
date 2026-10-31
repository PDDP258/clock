# MikuFocus

运行在专用音乐播放器 **M500**（初音未来联名，Android 14 定制 ROM /
骁龙 680 / 5 英寸 1280×720）上的**余光番茄钟**：机身右上左下横放在
桌角，后台音乐外放，你只用余光瞟屏幕，全程靠**机身侧边实体媒体键**
（上一曲 / 播放暂停 / 下一曲）操作，不触屏。

包名：`com.aiclock.player`（涉及 `android/app/build.gradle.kts` 的
applicationId 与 `lib/main.dart` 通知渠道 id 两处）。

## 使用场景即设计

设备放在桌角、处于**视野余光范围**，交互靠提示音 + 实体键。屏幕的
任务不是「被阅读」，而是「半秒瞟一眼就懂状态」。由此推出余光三原则：

1. **颜色报状态**——整屏底色随阶段染色（专注/休息/待继续），阶段
   切换时 700ms 渐变 + 一次脉冲，余光无需聚焦即可感知；
2. **大字报时间**——240sp 辉光巨字（等宽数字），一米外直接可读；
   每位数字独立 odometer 滚动，暂停时数字变**空心描边**——
   「时间被掏空」就是停了；
3. **不求助时无杂物**——平时只有阶段字标 + 时间 + 轮次豆；唯一
   「屏幕求人」的时刻是暂停/待继续：呼吸感大字提示「按播放键继续」。

动画纪律：只允许**慢**（6s 进度条流光）与**一次性**（阶段脉冲、
轮次豆弹出、开屏入场）两类动画，暂停即全停。

## 核心机制

- M500 实体键为主板直连的标准媒体键码（88 / 85 / 87），事件直达
  当前活跃 MediaSession，无蓝牙 AVRCP 丢包问题。
- 内建 `FocusAudioHandler`：开始专注时激活本 App 的 MediaSession
  并循环播放静音 keep-alive，**接管实体按键**；结束/暂停超阈值
  （默认 10 分钟）后 `setActive(false)` **归还给系统音乐 App**。
- **双按 = 音乐下一首**：本 App 先释放会话，经原生
  `AudioManager.dispatchMediaKeyEvent` 把 NEXT 转发给音乐 App，
  700ms 后自动重新接管——**计时与音乐共用同一组按键**。
- 计时引擎基于**时间戳差值**（非每秒累加），状态 JSON 持久化，
  杀后台/息屏后自动恢复并补齐流逝时间；息屏跟随系统，照常计时。
- 每次按键均有提示音 + 震动即时反馈；统计**秒级实时入账**
  （每 10s 周期结算），不等一轮结束。

## 按键映射（可在设置页编辑器自定义，热生效）

| 按键 | 手势 | 功能 |
| --- | --- | --- |
| 播放/暂停 | 单按 | 开始 / 暂停（经 300ms 多击窗口） |
| 播放/暂停 | 双按 | **转发「下一首」给音乐 App** |
| 播放/暂停 | 长按 | 结束本次专注并保存 |
| 下一曲 | 单按 | 跳过当前阶段 |
| 上一曲 | 单按 | +5 分钟（正计时 = 打时间标记点） |

单/双按共用一个键，300ms 是平台标准双击窗口的必要代价；在映射
编辑器解绑全部多击手势后，单按立即下发（<100ms）。FN 键不进标准
媒体键通道（ROM 拦截），不可用。

## 计时模式

- **番茄倒计时**（默认 25/5，每 4 轮长休；50/10 深度工作预设）：
  专注结束自动进休息，**一轮结束停在待继续**——休息与否由你按键
  决定，不自动续轮。
- **正计时**：自由累计时长，随时打标记点。

## 个性化

- **三套初音主题**（经典葱色 / 樱未来 / 雪未来），整屏染色随之切换；
- **四元素配色自定义**（专注/休息 × 时钟/进度条，五色调色板）；
- **辉光亮度**滑杆（0 = 关闭，余光省电场景可调低）。

## 统计

- 今日/本周时长与轮数，秒级实时更新；
- **近 12 周热力图**：自设每日及格线，达标满色、不足按差距二次方
  变浅、超标二次方向白变亮；点按格子查当天明细；
- **详细时间统计子页**：指定日期的 24h 时间轴（专注块/中断细条/
  休息空隙），可切换日期；
- 弹性连续记录（每周 2 天缓冲，断签不清零）、每周报告（环比 +
  最专注时段）、任务标签（会话开始烙印，可复盘）；
- 各应用使用时长（UsageStats，需授权）；一键删除全部数据。

## 架构

```
┌──────────────────────── M500 实体键 ────────────────────────┐
│  上一曲(88)   播放/暂停(85)   下一曲(87)                     │
└──────┬──────────────┬────────────────┬──────────────────────┘
       ▼              ▼                ▼
 MediaButtonReceiver → AudioService（前台服务, mediaPlayback）
       │
       ▼
 FocusAudioHandler ── 静音 keep-alive 霸占 MediaSession
       │  play/pause → ClickGrouper（300ms 多击窗口，可绕过）
       │  双按转发 → MethodChannel → AudioManager.dispatchMediaKeyEvent
       ▼
 MediaKeyEvent（语义事件，纯 Dart）
       ▼
 CommandBus ── KeyMapConfig 可重映射 ──▶ AppCommand
       ▼
 FocusController (Riverpod) ──▶ TimerEngine（纯 Dart 状态机,
       │                             时间戳差值计时, toJson/fromJson）
       ▼
 FocusPage（横屏余光 UI）  StatsPage（drift）  SettingsPage
```

四层架构：`app/`（装配）→ `features/*`（功能插件）→ `core/*`
（纯 Dart，可 `dart test`）→ `platform/*`（系统能力抽象，真机/fake
双实现），下层不依赖上层。数据层 drift（SQLite）+ shared_preferences。

## 构建

> 本机 Flutter 环境已就绪（Flutter 3.41.0 stable / Dart 3.11.0 /
> JDK 21 JBR）。环境清单与踩坑记录见
> [docs/本机Flutter环境使用说明.md](docs/本机Flutter环境使用说明.md)。

```bash
export PATH="/c/flutter/flutter/bin:$PATH"   # Git Bash 每次先执行
flutter pub get
dart run build_runner build                  # drift 代码生成（改表后必跑）
python tool/generate_audio.py                # 生成静音 keep-alive WAV
flutter test                                 # 135 个用例
flutter analyze                              # 基线：仅 2 条脚手架遗留 info
flutter build apk --release                  # 产物 build/app/outputs/flutter-apk/
```

注意：

- `pubspec.yaml` 已钉 `dependency_overrides: sqlparser: 0.44.5`
  （drift_dev 2.34.0 与 sqlparser 0.44.6 不兼容），升级 drift 系时
  需联动复核；
- drift DAO 注解用 `@DriftAccessor`（旧别名 `@DriftDao` 在
  analyzer 10 下无法解析）。

## M500 真机测试要点

1. **按键接管**：开始专注 → 实体键控制计时；结束或暂停超阈值后打开
   系统音乐 App，确认按键已交还。
2. **双按转发**：计时中双按播放键，音乐 App 应切下一首，且本 App
   不误触发跳过阶段（有回环守卫）。
3. **杀后台恢复**：专注中 `adb shell am kill com.aiclock.player`，
   重进确认倒计时按墙上时间正确推进（死亡期间到点自动轮转）。
4. **息屏**：锁屏 10 分钟计时照走（时间戳引擎 + 前台服务）。
5. **通知**：授予通知权限；通知显示「阶段 · 剩余 · 第 N 轮」分钟级
   文本（刻意防闪烁），按钮随运行态切换。
6. **余光页**：横屏放一米外，确认「颜色报状态 / 大字读时间 /
   暂停空心字」三信号不需聚焦即可接收。

## 已知限制（诚实清单）

- FN 键被 ROM 拦截、不上报标准键码，无法接入；
- 息屏状态下与音乐 App 的按键仲裁存在 ROM 级双触发可能（待取证）；
- 跨天会话整段归开始日统计（归因简化）。

## 文档地图

| 文档 | 用途 |
| --- | --- |
| [docs/01-市场调研报告.md](docs/01-市场调研报告.md) | 调研结论 |
| [docs/02-PRD-产品需求文档.md](docs/02-PRD-产品需求文档.md) | 功能边界 |
| [docs/03-技术架构设计.md](docs/03-技术架构设计.md) | 技术实现 |
| [docs/adr/](docs/adr/) | 5 条架构决策记录（ADR-0001~0005） |
| [CONTEXT.md](CONTEXT.md) | 领域词汇表 |
| [AGENT.md](AGENT.md) | 实施进度看板与经验记录 |
