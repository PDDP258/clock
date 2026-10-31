/// 每周结构化洞察模型（V0.5 AI 周报解读，纯 Dart）。
///
/// 数字与判定全部由本地 InsightEngine 算好，云端 LLM 只做润色。
/// [toUploadJson] 为**白名单序列化**（07 §5.1）：手工逐字段列出，
/// 新增字段默认不进上传体——从代码结构上防隐私泄漏。
library;

import '../../features/stats/domain/weekly_report.dart';

/// 一周专注的结构化洞察（仅存本地；上传时经 [toUploadJson] 白名单过滤）。
class WeeklyInsight {
  const WeeklyInsight({
    required this.thisWeekMinutes,
    required this.lastWeekMinutes,
    required this.changeRatio,
    required this.sessionCount,
    required this.rounds,
    required this.slotDistribution,
    required this.bestSlot,
    required this.streakDays,
    required this.bufferUsed,
    required this.interruptionCount,
    required this.interruptionMinutes,
    required this.interruptionSlotDistribution,
    required this.interruptionRatio,
    required this.avgInterruptionMinutes,
    required this.longestSegmentMinutes,
    required this.longestSegmentSlot,
    required this.bestDayWeekday,
    required this.bestDayMinutes,
    required this.activeDays,
    required this.daysElapsed,
  });

  /// 本周（周一至今）专注分钟
  final int thisWeekMinutes;

  /// 上周**同期**专注分钟（上周一至与本周相同的进度点，见 weekly_report.dart）
  final int lastWeekMinutes;

  /// 环比上周同期的变化率（0.2 = +20%）；上周同期无基线为 null（不误导）
  final double? changeRatio;

  /// 本周会话次数
  final int sessionCount;

  /// 本周完成轮数（正计时会话 rounds=0）
  final int rounds;

  /// 本周时段分布（时段 → 占比 0~1），只含非零桶
  final Map<DaySlot, double> slotDistribution;

  /// 本周最专注时段；无数据为 null
  final DaySlot? bestSlot;

  /// 弹性连续天数（US-D03）
  final int streakDays;

  /// 当前 7 天窗口已用缓冲天数
  final int bufferUsed;

  /// 本周中断次数（专注内暂停，US-D02）
  final int interruptionCount;

  /// 本周中断总分钟（未闭合的进行中暂停只计次数不计时长）
  final int interruptionMinutes;

  /// 本周中断**按次数**的时段分布（时段 → 占比 0~1），只含非零桶。
  ///
  /// 用次数而非时长：未闭合的进行中暂停没有时长，用次数才不会漏计
  /// （08-B3——「怎样减少中断」这题过去无数据可答，LLM 手里只有两个数）。
  final Map<DaySlot, double> interruptionSlotDistribution;

  /// 中断时长 / 专注时长（0.2 = 20%）；本周无专注为 null。
  /// 本地算好是为了让 LLM 不必自己做除法（prompt 明令禁止它算）。
  final double? interruptionRatio;

  /// 单次中断平均分钟（四舍五入）；无中断为 0
  final int avgInterruptionMinutes;

  /// 本周最长连续专注段（分钟）；无会话为 0
  final int longestSegmentMinutes;

  /// 最长段开始的时段；无会话为 null
  final DaySlot? longestSegmentSlot;

  /// 本周最专注的一天（1=周一 … 7=周日）；本周无记录为 null
  final int? bestDayWeekday;

  /// 最专注那天的专注分钟
  final int bestDayMinutes;

  /// 本周有专注记录的天数（对比 [streakDays] 更能说明「节奏是否连续」）
  final int activeDays;

  /// 本周已过天数（周一=1 … 周日=7）：本周是进行中的部分周（08-A1）
  final int daysElapsed;

  /// 解读门槛：本周专注不足 60 分钟且不足 3 次会话时，数据不足以支撑
  /// 有意义的复盘——此时不发请求（省一次必然产鸡汤的调用，08-A6）。
  bool get isSufficient =>
      thisWeekMinutes >= kMinMinutesForInsight ||
      sessionCount >= kMinSessionsForInsight;

  /// 数据指纹：缓存按周回看时用它判断「这份解读是不是已经过时」。
  /// 只用于本地比对，**不进 [toUploadJson]**（不上传）。
  String get dataFingerprint =>
      '$sessionCount|$thisWeekMinutes|$rounds|$interruptionCount';

  /// 白名单上传序列化：只允许 07 §4.1 表中的字段出设备。
  /// 中断来源无应用维度（US-D02 落地以暂停区间替代切出检测，
  /// 见 AGENT.md §7），故无 top_interruption_categories 字段。
  Map<String, dynamic> toUploadJson() => <String, dynamic>{
        'week_focus_minutes': thisWeekMinutes,
        'last_week_focus_minutes': lastWeekMinutes,
        'days_elapsed': daysElapsed,
        // 无基线时省略字段，不让 LLM 看到误导性的 0
        if (changeRatio != null)
          'change_ratio': double.parse(changeRatio!.toStringAsFixed(3)),
        'session_count': sessionCount,
        'rounds': rounds,
        'slot_distribution': <String, dynamic>{
          for (final e in slotDistribution.entries)
            e.key.label: double.parse(e.value.toStringAsFixed(3)),
        },
        'streak_days': streakDays,
        'buffer_used': bufferUsed,
        'interruption_count': interruptionCount,
        'interruption_minutes': interruptionMinutes,
        // 08-B3 扩充：中断的时段分布与占比——「怎样减少中断」这题过去
        // 手里只有次数与总时长两个数，答不出「你的中断集中在晚上」。
        // 与 slot_distribution 同性质的时段聚合，无应用名/内容维度。
        if (interruptionSlotDistribution.isNotEmpty)
          'interruption_slot_distribution': <String, dynamic>{
            for (final e in interruptionSlotDistribution.entries)
              e.key.label: double.parse(e.value.toStringAsFixed(3)),
          },
        if (interruptionRatio != null)
          'interruption_ratio':
              double.parse(interruptionRatio!.toStringAsFixed(3)),
        'avg_interruption_minutes': avgInterruptionMinutes,
        'longest_segment_minutes': longestSegmentMinutes,
        if (longestSegmentSlot != null)
          'longest_segment_slot': longestSegmentSlot!.label,
        if (bestDayWeekday != null)
          'best_day_label': weekdayLabel(bestDayWeekday!),
        'best_day_minutes': bestDayMinutes,
        'active_days': activeDays,
      };
}

/// 周一=1 … 周日=7 → 中文展示名（事实块与上传体共用同一份映射）。
String weekdayLabel(int weekday) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];

/// 解读门槛常量（08-A6）：本周专注分钟下限。
const int kMinMinutesForInsight = 60;

/// 解读门槛常量（08-A6）：本周会话数下限（够 3 段就算有节奏可言）。
const int kMinSessionsForInsight = 3;
