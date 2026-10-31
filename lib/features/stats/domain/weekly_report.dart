/// 每周专注报告（US-D04，纯 Dart 可测）：本周总量、上周同期环比、最专注时段。
///
/// 周 = ISO 周（周一开始）。最专注时段按会话 startAt 的本地小时分四桶，
/// 以实际专注毫秒求和取最大（粗粒度：跨时段会话整段归开始时段，
/// 与 §7 跨天归因限制同级的诚实简化）。
///
/// **环比口径（08-A1，2026-09-25 修正）**：本周天然是「周一至今」的部分周，
/// 若拿它直接比上周**完整**一周，周一上午会得出接近 -100% 的假退步
/// （本周 25 分钟 vs 上周 600 分钟），而 AI 解读被要求原样引用数字，
/// 会把这种假退步当成结论说出来。故 [lastWeekMillis] 改为
/// **上周同期**：上周一只取到与本周相同的进度点（同为周三 15:00 时，
/// 上周基线 = 上周一 00:00 ~ 上周三 15:00），保证两个口径可比。
library;

/// 一天四个时段。
enum DaySlot { dawn, morning, afternoon, evening }

/// 时段中文展示名。
extension DaySlotX on DaySlot {
  /// 展示名
  String get label => switch (this) {
        DaySlot.dawn => '凌晨',
        DaySlot.morning => '上午',
        DaySlot.afternoon => '下午',
        DaySlot.evening => '晚上',
      };
}

/// 本地小时 → 时段：凌晨 0-6 / 上午 6-12 / 下午 12-18 / 晚上 18-24。
DaySlot slotOfHour(int hour) {
  if (hour >= 6 && hour < 12) return DaySlot.morning;
  if (hour >= 12 && hour < 18) return DaySlot.afternoon;
  if (hour >= 18) return DaySlot.evening;
  return DaySlot.dawn;
}

/// 周报数据。
class WeeklyReport {
  const WeeklyReport({
    required this.thisWeekMillis,
    required this.lastWeekMillis,
    required this.changeRatio,
    required this.bestSlot,
    required this.bestSlotMillis,
    required this.daysElapsed,
  });

  /// 本周（周一至今）实际专注毫秒
  final int thisWeekMillis;

  /// 上周**同期**实际专注毫秒（上周一至与本周相同的进度点，08-A1）
  final int lastWeekMillis;

  /// 环比上周同期的变化率（0.2 = +20%）；上周同期无数据时为 null（无基线，不误导）
  final double? changeRatio;

  /// 本周最专注时段；本周无数据为 null
  final DaySlot? bestSlot;

  /// 最专注时段的专注毫秒
  final int bestSlotMillis;

  /// 本周已过天数（周一=1 … 周日=7），供 UI/prompt 声明「部分周」
  final int daysElapsed;
}

/// 由会话列表构建周报。[sessions] 元素 = (会话开始毫秒, 实际专注毫秒)，
/// 调用方负责提供覆盖「上周一 ~ 本周末」区间的数据。
WeeklyReport buildWeeklyReport(List<(int, int)> sessions, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final thisWeekStart =
      today.subtract(Duration(days: today.weekday - 1)).millisecondsSinceEpoch;
  final lastWeekStart =
      thisWeekStart - const Duration(days: 7).inMilliseconds;
  // 上周同期截止点 = 上周一 + 本周已过去的时长（08-A1）
  final lastWeekCutoff =
      lastWeekStart + (now.millisecondsSinceEpoch - thisWeekStart);

  var thisWeek = 0;
  var lastWeek = 0;
  final slotTotals = <DaySlot, int>{};
  for (final (startAt, focusMillis) in sessions) {
    if (startAt >= thisWeekStart) {
      thisWeek += focusMillis;
      final slot =
          slotOfHour(DateTime.fromMillisecondsSinceEpoch(startAt).hour);
      slotTotals[slot] = (slotTotals[slot] ?? 0) + focusMillis;
    } else if (startAt >= lastWeekStart && startAt < lastWeekCutoff) {
      lastWeek += focusMillis;
    }
  }

  DaySlot? bestSlot;
  var bestMillis = 0;
  for (final e in slotTotals.entries) {
    if (e.value > bestMillis) {
      bestSlot = e.key;
      bestMillis = e.value;
    }
  }

  return WeeklyReport(
    thisWeekMillis: thisWeek,
    lastWeekMillis: lastWeek,
    changeRatio: lastWeek > 0 ? (thisWeek - lastWeek) / lastWeek : null,
    bestSlot: bestSlot,
    bestSlotMillis: bestMillis,
    daysElapsed: today.weekday,
  );
}
