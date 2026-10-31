/// 本地洞察引擎（V0.5，纯 Dart 可测）：两周会话事实 → 结构化洞察。
///
/// 复用 stats 域既有组件：buildWeeklyReport（总量/环比/最专注时段）、
/// slotOfHour（时段四桶）；中断聚合来自会话的专注内暂停区间（US-D02）。
/// 「算什么、判断什么」全在这里；LLM 只负责「怎么说」（ADR-0006）。
///
/// 08-B3（2026-09-26）扩充：中断的时段分布、中断占比与单次均值、
/// 最长连续段（含所在时段）、最专注的一天、有记录天数——**这批数据一直
/// 就在库里，此前只被累加成了计数**。补齐后 LLM 才有「关系」可讲，
/// 而不只是复述总量（用户反馈「AI 太枯燥」的物质层面原因：没什么可说的）。
library;

import '../../features/stats/domain/elastic_streak.dart';
import '../../features/stats/domain/weekly_report.dart';
import 'insight.dart';

/// 一条会话的洞察输入事实（由落库层从 drift 行折算）。
class InsightSessionFact {
  const InsightSessionFact({
    required this.startAtMillis,
    required this.focusMillis,
    required this.rounds,
    this.pauses = const <(int, int?)>[],
  });

  /// 会话开始墙上时间戳（毫秒）
  final int startAtMillis;

  /// 实际专注毫秒
  final int focusMillis;

  /// 完成轮数（正计时为 0）
  final int rounds;

  /// 专注内暂停（中断）区间（开始毫秒, 结束毫秒；null = 结算时仍暂停中）
  final List<(int, int?)> pauses;
}

/// ISO 周缓存键（如 '2026-W35'）：解读缓存按周易位，同周回看不重复请求。
String isoWeekKey(DateTime date) {
  final thursday = date.add(Duration(days: 4 - date.weekday));
  final yearStart = DateTime(thursday.year, 1, 1);
  final week = (thursday.difference(yearStart).inDays / 7).floor() + 1;
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}

/// 由两周窗口（上周一 ~ 现在）的会话事实构建结构化洞察。
/// [streak] 由调用方用既有 elasticStreak 算好传入（它需要 400 天回看，
/// 与两周窗口不是同一份数据，不进本函数）。
WeeklyInsight buildWeeklyInsight({
  required List<InsightSessionFact> sessions,
  required StreakResult streak,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final thisWeekStart =
      today.subtract(Duration(days: today.weekday - 1)).millisecondsSinceEpoch;

  // 总量/环比/最专注时段复用既有周报算法（口径一致，不另造）
  final report = buildWeeklyReport(
    [for (final s in sessions) (s.startAtMillis, s.focusMillis)],
    now,
  );

  var sessionCount = 0;
  var rounds = 0;
  var interruptionCount = 0;
  var interruptionMillis = 0;
  final slotTotals = <DaySlot, int>{};
  // 08-B3：pauses 本来就带时间戳，此前只累加计数——「中断集中在哪个时段」
  // 是「怎样减少中断」唯一能给出具体答案的依据，白白丢掉了。
  final interruptionSlotCounts = <DaySlot, int>{};
  var longestSegmentMillis = 0;
  DaySlot? longestSegmentSlot;
  // 按本地自然日聚合：定位「最专注的一天」与「有记录的天数」
  final dayTotals = <DateTime, int>{};
  for (final s in sessions) {
    if (s.startAtMillis < thisWeekStart) continue; // 上周只进周报基数
    sessionCount++;
    rounds += s.rounds;
    final startedAt = DateTime.fromMillisecondsSinceEpoch(s.startAtMillis);
    final slot = slotOfHour(startedAt.hour);
    slotTotals[slot] = (slotTotals[slot] ?? 0) + s.focusMillis;
    if (s.focusMillis > longestSegmentMillis) {
      longestSegmentMillis = s.focusMillis;
      longestSegmentSlot = slot;
    }
    final day = DateTime(startedAt.year, startedAt.month, startedAt.day);
    dayTotals[day] = (dayTotals[day] ?? 0) + s.focusMillis;
    for (final (pStart, pEnd) in s.pauses) {
      interruptionCount++;
      // 中断计入「暂停发生」的时段（用次数而非时长：未闭合暂停没有时长）
      final pauseSlot =
          slotOfHour(DateTime.fromMillisecondsSinceEpoch(pStart).hour);
      interruptionSlotCounts[pauseSlot] =
          (interruptionSlotCounts[pauseSlot] ?? 0) + 1;
      if (pEnd != null && pEnd > pStart) {
        interruptionMillis += pEnd - pStart;
      }
    }
  }

  DateTime? bestDay;
  var bestDayMillis = 0;
  for (final e in dayTotals.entries) {
    if (e.value > bestDayMillis) {
      bestDay = e.key;
      bestDayMillis = e.value;
    }
  }

  const minuteMillis = 60 * 1000;
  final thisWeekTotal = report.thisWeekMillis;
  return WeeklyInsight(
    thisWeekMinutes: thisWeekTotal ~/ minuteMillis,
    // lastWeekMillis 已是对齐进度的「上周同期」口径（08-A1），
    // 故环比不再被「部分周 vs 完整周」系统性压低
    lastWeekMinutes: report.lastWeekMillis ~/ minuteMillis,
    changeRatio: report.changeRatio,
    sessionCount: sessionCount,
    rounds: rounds,
    slotDistribution: <DaySlot, double>{
      if (thisWeekTotal > 0)
        for (final e in slotTotals.entries)
          e.key: e.value / thisWeekTotal,
    },
    bestSlot: report.bestSlot,
    streakDays: streak.days,
    bufferUsed: streak.bufferUsed,
    interruptionCount: interruptionCount,
    interruptionMinutes: interruptionMillis ~/ minuteMillis,
    interruptionSlotDistribution: <DaySlot, double>{
      if (interruptionCount > 0)
        for (final e in interruptionSlotCounts.entries)
          e.key: e.value / interruptionCount,
    },
    // 占比与均值在本地算好，LLM 不必自己做除法（prompt 明令禁止它算）
    interruptionRatio:
        thisWeekTotal > 0 ? interruptionMillis / thisWeekTotal : null,
    avgInterruptionMinutes: interruptionCount > 0
        ? (interruptionMillis / minuteMillis / interruptionCount).round()
        : 0,
    longestSegmentMinutes: longestSegmentMillis ~/ minuteMillis,
    longestSegmentSlot: longestSegmentSlot,
    bestDayWeekday: bestDay?.weekday,
    bestDayMinutes: bestDayMillis ~/ minuteMillis,
    activeDays: dayTotals.length,
    // 周一=1 … 周日=7：本周是进行中的部分周，prompt 需如实声明（08-A1）
    daysElapsed: today.weekday,
  );
}
