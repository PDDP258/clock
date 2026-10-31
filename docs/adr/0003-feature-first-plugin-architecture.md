# ADR-0003：Feature-first 插件化架构 + Riverpod 依赖注入 + Command 映射层

**Status**: Accepted (2026-07-19)

> 注（2026-07-19）：文中版本路线图与 US 编号为历史记录，已被 [ADR-0005](./0005-simplicity-experience-first.md) 修订（拦截/游戏化砍除、按键自定义编号变为 US-A08）；本 ADR 的架构决策（Feature-first 插件化 + Riverpod + Command 映射层）不受影响，继续有效。

关联：[技术架构设计-第 1/3/9 节](../03-技术架构设计.md)、[PRD-版本路线图](../02-PRD-产品需求文档.md)

## Context

产品路线图为 V0.1（按键计时 MVP）→ V0.2（数据收集+报告）→ V0.3（拦截/学霸模式）→ V0.4（目标习惯+游戏化）→ V1.0（账号云同步+开放平台）。每个版本叠加一个功能域，且存在两类裁剪需求：

- **版本裁剪**：MVP 只发布部分功能，其余功能后续启用；
- **渠道裁剪**：应用拦截（AccessibilityService）有 Play 审核风险（ADR-0004），Play 版需发布无拦截变体。

同时，按键语义（单按/双按/三按/长按/上一曲/下一曲 → 业务动作）需支持用户自定义（US-J02），且 FN 快捷键、音量旋钮是明确的 V0.x 扩展点——按键处理链路必须把「事件解析」与「业务动作」解耦。

若采用按层分包（layer-first：pages/blocs/models 各一目录），功能横跨多目录，增删一个功能牵动全局，无法裁剪与独立测试。

## Decision

1. **Feature-first 目录**：每个功能域（focus / stats / usage / blocker / goals / gamification / settings / sync）独立目录，自含 UI、状态、Repository 绑定；增删功能 = 增删目录 + 装配层一行注册；
2. **Riverpod 依赖注入**：所有跨层依赖经 Provider 注入，测试与渠道变体用 override 替换实现（如拦截模块在 Play 变体中替换为空实现）；
3. **Command 映射层**：按键事件先解析为中性 Command（start/pause/resume/plus5min/skip/end/undo…），再由可配置映射表绑定到业务动作；映射表持久化，运行时可改；新增输入源（FN 键、音量旋钮）只需接入解析器，不触碰计时引擎；
4. 分层遵守「App 装配层 → Feature 功能层 → Core 核心层（纯 Dart）→ Platform 适配层」的依赖方向（见 [技术架构设计-第 1 节](../03-技术架构设计.md)）。

## Consequences

**正面**：
- 版本路线图中的每个功能可独立开发、独立测试、按版本/渠道插拔，直接支撑 MVP 快速发布与 V0.3 的渠道裁剪；
- 按键可配置（US-J02）与 FN/旋钮扩展零引擎改动；
- Core 层纯 Dart，计时引擎与按键解析可脱离 Flutter 单测（PRD-Testing Decisions）。

**负面**：
- 功能间共享组件（卡片、对话框）需约定放入共享目录，否则易重复；以 code review 与 lint 约束；
- Provider 装配集中在一处，需文档化注册顺序，避免隐式依赖。

**替代方案放弃原因**：layer-first 无法满足功能裁剪与独立演进；Bloc/GetX 等方案在可覆盖性与测试便利性上不及 Riverpod。
