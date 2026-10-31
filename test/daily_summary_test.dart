/// 每日小结纯函数单测（看板 #46）。
library;

import 'package:ai_clock/features/stats/domain/daily_summary.dart';
import 'package:ai_clock/features/stats/domain/weekly_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 2026-09-12 是周六；构造当日不同时刻
  int at(int hour, [int minute = 0]) =>
      DateTime(2026, 9, 12, hour, minute).millisecondsSinceEpoch;

  test('空日：全零、最佳时段 null', () {
    final s = buildDailySummary(const []);
    expect(s.focusMillis, 0);
    expect(s.rounds, 0);
    expect(s.sessionCount, 0);
    expect(s.interruptionCount, 0);
    expect(s.bestSlot, isNull);
  });

  test('多会话聚合：时长/轮数/会话数求和', () {
    final s = buildDailySummary([
      DailySessionFact(startAtMillis: at(9), focusMillis: 1500000, rounds: 1),
      DailySessionFact(startAtMillis: at(14), focusMillis: 3000000, rounds: 2),
    ]);
    expect(s.focusMillis, 4500000);
    expect(s.rounds, 3);
    expect(s.sessionCount, 2);
  });

  test('中断：次数含未闭合，时长只计已闭合', () {
    final s = buildDailySummary([
      DailySessionFact(
          startAtMillis: at(9),
          focusMillis: 1500000,
          rounds: 1,
          pauses: [(at(9, 5), at(9, 7)), (at(9, 10), null)]),
    ]);
    expect(s.interruptionCount, 2);
    expect(s.interruptionMillis, 120000);
  });

  test('最佳时段取专注毫秒最大的桶', () {
    final s = buildDailySummary([
      DailySessionFact(startAtMillis: at(9), focusMillis: 600000, rounds: 1),
      DailySessionFact(startAtMillis: at(15), focusMillis: 1800000, rounds: 1),
    ]);
    expect(s.bestSlot, DaySlot.afternoon);
  });

  test('零时长会话不参与时段分桶', () {
    final s = buildDailySummary([
      DailySessionFact(startAtMillis: at(23), focusMillis: 0, rounds: 0),
      DailySessionFact(startAtMillis: at(8), focusMillis: 600000, rounds: 1),
    ]);
    expect(s.bestSlot, DaySlot.morning);
  });

  test('起止与最长一段：多会话取最早开始/最晚结束/最大单段', () {
    final s = buildDailySummary([
      DailySessionFact(startAtMillis: at(14), focusMillis: 3000000, rounds: 2),
      DailySessionFact(startAtMillis: at(9), focusMillis: 1500000, rounds: 1),
    ]);
    expect(s.firstStartMillis, at(9));
    // 最晚结束 = 14:00 + 50 分钟
    expect(s.lastEndMillis, at(14, 50));
    expect(s.longestSegmentMillis, 3000000);
  });

  test('空日：起止为 null，最长一段为 0', () {
    final s = buildDailySummary(const []);
    expect(s.firstStartMillis, isNull);
    expect(s.lastEndMillis, isNull);
    expect(s.longestSegmentMillis, 0);
  });
}
