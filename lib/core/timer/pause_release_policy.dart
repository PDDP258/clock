/// 暂停超时释放策略（US-C02，纯 Dart 可单测）。
///
/// 语义：暂停超过阈值（默认 10 分钟，可配置）→ 释放 MediaSession，
/// 实体按键归还 M500 系统音乐 App，但专注记录**不作废**（弹性中断，
/// 替代「中断即作废」的挫败设计）；用户继续时重新霸占按键。
///
/// 自动结束（真机反馈 R7）：暂停/待继续超过 [defaultAutoFinishThreshold]
/// （60 分钟）→ 会话整体结束（最终结算 + 复位 + 释放）。背景：M500 ROM
/// 媒体键双触发（保留项）会把音乐 App 的按键漏进本 App，「待继续」被
/// 幽灵 resume 一轮轮空跑记出假统计；自动结束把单次不活跃期的幽灵累积
/// 限制在最多一轮，也让离开数小时的用户回来时看到干净的全新开始。
library;

/// 暂停释放策略。
abstract final class PauseReleasePolicy {
  /// 默认阈值：10 分钟（PRD US-C02）。
  static const Duration defaultThreshold = Duration(minutes: 10);

  /// 不活跃自动结束阈值：60 分钟（R7）。
  /// 远长于正常轮间歇（用户喝口水、回个消息），远短于一午休；
  /// 覆盖番茄 paused（含「待继续」）与正计时 paused 两种暂停态。
  static const Duration defaultAutoFinishThreshold = Duration(minutes: 60);

  /// 是否应释放按键：暂停时刻起算，达到阈值即释放（边界含等于）。
  static bool shouldRelease({
    required int pausedAtMillis,
    required int nowMillis,
    required Duration threshold,
  }) {
    return nowMillis - pausedAtMillis >= threshold.inMilliseconds;
  }

  /// 是否应自动结束会话：暂停时刻起算，达到阈值即结束（边界含等于）。
  /// 与 [shouldRelease] 同形但语义独立——释放是归还按键，结束是关闭会话。
  static bool shouldAutoFinish({
    required int pausedAtMillis,
    required int nowMillis,
    required Duration threshold,
  }) {
    return nowMillis - pausedAtMillis >= threshold.inMilliseconds;
  }
}
