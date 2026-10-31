# 应用拦截（V0.3 预留）

## 目标

专注计时期间，拦截用户打开「黑名单」应用（如阅读器、浏览器），
或限制其当日累计使用时长；白名单应用（如本 App、系统音乐）不受影响。

## 数据基础（已就位）

- drift 表 `app_rule`（见 `lib/platform/db/app_database.dart`）：
  `ruleType = whitelist / blacklist / limit`，`dailyLimitMillis` 为限时上限。
- `UsageStatsSource`：按日读取各应用前台时长，作为限时规则的判定输入。

## 技术方案

### 首选：AccessibilityService

- 注册 `AccessibilityService`，监听 `TYPE_WINDOW_STATE_CHANGED`，
  拿到前台应用包名；
- 命中黑名单且专注进行中 → 全屏覆盖层（`TYPE_ACCESSIBILITY_OVERLAY`）
  或直接 `performGlobalAction(GLOBAL_ACTION_HOME)` 弹回桌面；
- 优点：不依赖系统定制，M500 Android 14 可用；
- 缺点：需用户手动在无障碍设置中开启，引导成本高。

### 备选：UsageStats 轮询

- 前台服务内每 1~2s 轮询 `UsageStatsManager.queryEvents` 取前台包名；
- 实现简单，但命中延迟较高（秒级），体验弱于无障碍方案。

## 政策与合规风险

- **本 App 面向 M500 专用设备、非 Google Play 分发**，Play 的
  AccessibilityService 政策（需声明用途、限制滥用）不构成直接约束；
  若未来上架 Play，需提前评估「无障碍 API 用于应用拦截」的合规声明。
- 拦截行为必须可由用户显式开关，且规则仅作用于本机，不上传任何
  应用列表数据。

## 接入点

- 规则读写：drift `app_rule` 表 + 设置页新增「应用规则」入口；
- 拦截判定：新增 `BlockingController`（Riverpod），订阅
  `focusControllerProvider`，专注中才激活判定循环；
- 包名获取：上述 AccessibilityService / UsageStats 二选一，
  封装在 `core/platform/` 下的抽象后，避免散落到业务层。
