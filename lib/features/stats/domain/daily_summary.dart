/// 每日小结（看板 #46，纯 Dart 可测）：指定日的专注聚合——
/// 时长/轮数/会话数/中断/最佳时段，详细时间统计页顶部「今日小结」卡用。
///
/// 口径与周报一致（weekly_report.dart）：时段按会话 startAt 本地小时四桶、
/// 中断来自专注内暂停区间（US-D02），全部是既有诚实口径的当日粒度复用。
library;

import 'weekly_report.dart';

/// 一条会话的当日小结输入事实（由 db 行映射而来，本文件不依赖 drift）。
class DailySessionFact {
  const DailySessionFact({
    required this.startAtMillis,
    required this.focusMillis,
    required this.rounds,
    this.pauses = const [],
  });

  /// 会话开始时刻（毫秒时间戳）
  final int startAtMillis;

  /// 实际专注毫秒
  final int focusMillis;

  /// 完成轮数
  final int rounds;

  /// 专注内暂停（中断）区间 [(start, end?)]，end 为 null = 暂停未闭合
  final List<(int, int?)> pauses;
}

/// 当日小结。
class DailySummary {
  const DailySummary({
    required this.focusMillis,
    required this.rounds,
    required this.sessionCount,
    required this.interruptionCount,
    required this.interruptionMillis,
    required this.bestSlot,
    required this.firstStartMillis,
    required this.lastEndMillis,
    required this.longestSegmentMillis,
  });

  /// 当日实际专注总毫秒
  final int focusMillis;

  /// 当日完成番茄数
  final int rounds;

  /// 当日会话条数
  final int sessionCount;

  /// 中断（专注内暂停）次数；未闭合的只计次数
  final int interruptionCount;

  /// 中断总毫秒（只计已闭合区间）
  final int interruptionMillis;

  /// 最佳时段（专注毫秒最大的桶）；当日无专注为 null
  final DaySlot? bestSlot;

  /// 当日最早一条会话的开始时刻；无会话为 null
  final int? firstStartMillis;

  /// 当日最晚结束时刻（startAt + 实际专注时长近似）；无会话为 null
  final int? lastEndMillis;

  /// 最长单段专注毫秒（所有会话中的最大值）；无会话为 0
  final int longestSegmentMillis;

  /// 数据指纹：当日点评缓存按日回看时用它判断内容是否已过时（08-A2）。
  /// 只用于本地比对，不参与任何上传。
  String get dataFingerprint =>
      '$sessionCount|$focusMillis|$rounds|$interruptionCount';
}

/// 聚合当日会话为小结。
DailySummary buildDailySummary(List<DailySessionFact> facts) {
  var focusMillis = 0;
  var rounds = 0;
  var interruptionCount = 0;
  var interruptionMillis = 0;
  int? firstStartMillis;
  int? lastEndMillis;
  var longestSegmentMillis = 0;
  final slotMillis = <DaySlot, int>{};

  for (final f in facts) {
    focusMillis += f.focusMillis;
    rounds += f.rounds;
    if (firstStartMillis == null || f.startAtMillis < firstStartMillis) {
      firstStartMillis = f.startAtMillis;
    }
    // 结束点以 startAt + 实际专注近似（休息/暂停不计入跨度端点，
    // 对「从几点学到几点」的口径足够诚实）
    final end = f.startAtMillis + f.focusMillis;
    if (lastEndMillis == null || end > lastEndMillis) {
      lastEndMillis = end;
    }
    if (f.focusMillis > longestSegmentMillis) {
      longestSegmentMillis = f.focusMillis;
    }
    if (f.focusMillis > 0) {
      final slot =
          slotOfHour(DateTime.fromMillisecondsSinceEpoch(f.startAtMillis).hour);
      slotMillis[slot] = (slotMillis[slot] ?? 0) + f.focusMillis;
    }
    for (final (s, e) in f.pauses) {
      interruptionCount++;
      if (e != null && e > s) interruptionMillis += e - s;
    }
  }

  DaySlot? bestSlot;
  var best = 0;
  for (final e in slotMillis.entries) {
    if (e.value > best) {
      best = e.value;
      bestSlot = e.key;
    }
  }

  return DailySummary(
    focusMillis: focusMillis,
    rounds: rounds,
    sessionCount: facts.length,
    interruptionCount: interruptionCount,
    interruptionMillis: interruptionMillis,
    bestSlot: bestSlot,
    firstStartMillis: firstStartMillis,
    lastEndMillis: lastEndMillis,
    longestSegmentMillis: longestSegmentMillis,
  );
}
