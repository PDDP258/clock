# ADR-0001：用 audio_service + 静音保活霸占 MediaSession 接收实体按键

**Status**: Accepted (2026-07-19)

关联：[PRD-Implementation Decisions](../02-PRD-产品需求文档.md)、[技术架构设计-第 5 节](../03-技术架构设计.md)、[词汇表](../../CONTEXT.md)

## Context

产品核心交互是「用 M500 机身侧边实体媒体按键（播放/暂停=KEYCODE 85、下一曲=87、上一曲=88）控制番茄钟，熄屏/后台可用」。需要选择按键事件的接收方案：

1. **audio_service + MediaSession**：Android 标准媒体按键路由，audio_service 包支持 `androidForceEnableMediaButtons` 与静音保活（[pub.dev/packages/audio_service](https://pub.dev/packages/audio_service)）；
2. **无障碍服务（AccessibilityService）**：可全局监听按键，但权限敏感、Google Play 审核风险高（见 ADR-0004），且语义上与「媒体按键」不符；
3. **音量键/其他按键钩子**：需要前台或 overlay 权限，无法熄屏可用，且 M500 出厂未将计时语义映射到音量键。

M500 的特殊性：按键主板直连标准 KeyEvent 通道，本地可靠到达（无蓝牙耳机 AVRCP 到达率问题）；但设备本身是音乐播放器，**按键归属存在与音乐 App 的天然冲突**——听歌时按键应归音乐 App，计时开启时才归本 App。另外，后台/熄屏时按键由系统媒体路由分发，只有持有活跃 MediaSession 的 App 能收到，因此即使按键本地可靠，会话保活仍然必要。

## Decision

采用 **audio_service + 静音音频保活霸占 MediaSession** 方案：

1. 计时开启时：播放静音音频保持 MediaSession active + 启动 `mediaPlayback` 类型前台服务（Android 14 需声明 `FOREGROUND_SERVICE_MEDIA_PLAYBACK`），实体按键路由到本 App；
2. 计时结束（完成/用户结束/暂停超过默认 10 分钟阈值）时：**主动释放会话**（`setActive(false)`、停止静音播放、停止前台服务），按键归还音乐 App；
3. 提供「听歌时按键归属」设置项（默认：仅计时开启时归计时），音乐 App 主动播放时本 App 让出焦点并暂停计时；
4. 按键事件经 800ms 窗口多击计数与长按判定解析为 Command（映射可配置，见 [技术架构设计-5.2](../03-技术架构设计.md)）；
5. 拒绝无障碍与音量键方案：前者审核风险高且语义不符，后者无法熄屏可用。

## Consequences

**正面**：
- 标准系统能力，稳定性与兼容性最好；熄屏/后台可用；
- 与「媒体按键」语义一致，用户肌肉记忆（耳机线控操作）可直接迁移；
- 静音保活同时满足前台服务要求，计时不易被杀。

**负面与缓解**：
- **与音乐 App 冲突**：计时开启期间用户无法用按键控制音乐。缓解：明确的霸占/释放策略 + 归属设置项 + 首次引导 + 通知栏明示当前归属；焦点丢失时暂停计时而非异常；
- **静音保活耗电**：功耗低且 4500mAh 电池充裕，纳入真机 8h 耗电验收（风险 R5）；
- 首次霸占会话需要用户理解成本：以一次性引导与通知文案管理预期。
