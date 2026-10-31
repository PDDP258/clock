# ADR-0004：MVP 用 UsageStatsManager 轮询判定切出，AccessibilityService 拦截留到 V0.3

**Status**: Accepted (2026-07-19)

> 注（2026-07-19）：文中「拦截留到 V0.3」的排期与 US 编号为历史记录——应用拦截/学霸模式已被 [ADR-0005](./0005-simplicity-experience-first.md) 移出版本路线图（如需重启须另立 ADR），使用统计调整为 V0.3；本 ADR「UsageStats 优先、慎用无障碍」的技术判断继续有效。

关联：[技术架构设计-第 7/10 节](../03-技术架构设计.md)、[PRD-使用数据收集与 MVP 范围](../02-PRD-产品需求文档.md)

## Context

产品需要两种「感知用户在用什么 App」的能力：

1. **切出检测（Relapse detection）**：专注进行中判断用户是否切出到非白名单应用，用于统计与提醒（V0.2 需求，US-E03 / US-C02）；
2. **应用拦截（学霸模式）**：专注中阻止非白名单应用打开（V0.3 需求，US-F01）。

可选技术路径：

1. **UsageStatsManager 轮询**：通过 `usage_stats` 包（[pub.dev/packages/usage_stats](https://pub.dev/packages/usage_stats)）以 1-3 秒间隔轮询 `queryEvents`，依据最新 `MOVE_TO_FOREGROUND` 事件判定前台应用。权限为「使用情况访问」（PACKAGE_USAGE_STATS），属特殊权限但**不涉及无障碍**，审核风险低；缺点是只能「事后感知」（秒级延迟），无法真正阻止应用打开；
2. **AccessibilityService（如 flutter_accessibility_service）**：可实时感知窗口切换并执行拦截，体验强；但属高敏权限，**Google Play 对无障碍权限审核严格**，声明用途若与「残障辅助」无关容易被拒，存在上架风险。

M500 环境缓解了部分问题：封闭定制 ROM 分发以预装/厂商渠道为主，但产品仍可能进入 Play 及国内各应用市场，渠道政策差异必须前置考虑。另外 MVP 阶段的核心验证目标是「按键零触屏计时」，切出统计属于 V0.2，拦截属于 V0.3——早期引入高敏权限得不偿失。

## Decision

1. **MVP（V0.1-V0.2）采用 UsageStatsManager 轮询**判定切出违约：低权限、低审核风险，满足统计与提醒需求；未授权时功能降级为「仅计时」，不阻塞核心流程；
2. **AccessibilityService 拦截推迟到 V0.3**，仅用于学霸模式；发布策略为**国内渠道优先**（国内市场对无障碍类自律工具接受度高，如不做手机控/禅定空间均以重度权限实现锁机），Play 渠道发布无拦截变体；
3. 切出事件流在架构上抽象为统一接口（`feature_usage` 输出 Relapse 事件），V0.3 的 AccessibilityService 实现复用同一事件流，拦截引擎做成可按渠道裁剪的 Feature 插件（ADR-0003）；
4. 使用数据默认全部本地存储，任何上报须经 AnalyticsSink 抽象且用户明示同意。

## Consequences

**正面**：
- MVP 与 V0.2 无任何高敏权限，上架与授权转化阻力最小；
- 「先软后硬」（先统计提醒、后可选拦截）契合用户痛点 Top4/5（白名单繁琐、锁机误伤）的产品策略；
- 统一事件流抽象使 V0.3 拦截成为纯增量，不返工。

**负面**：
- 轮询存在 1-3 秒感知延迟，极短切出可能漏检：可接受（统计用途），在报告中标注口径；
- 轮询带来少量耗电：限制仅在计时进行中轮询，空闲停止；
- 双实现（UsageStats 感知 / Accessibility 拦截）长期并存，需要清晰的接口隔离与渠道构建变体管理。

**替代方案放弃原因**：MVP 直接使用 AccessibilityService 会引入 Play 审核风险与早期授权流失，且超出核心验证目标，投入产出不合理。
