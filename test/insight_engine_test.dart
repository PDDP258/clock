/// InsightEngine 单测（V0.5 AI 周报解读的本地规则引擎接缝）。
///
/// 语义要点：
/// - 输入为两周窗口的会话事实 + 弹性连续结果，输出结构化洞察；
/// - 环比上周无基线为 null（不误导），toUploadJson 同步省略该字段；
/// - 时段分布四桶（凌晨/上午/下午/晚上）占比，只含非零桶；
/// - 中断聚合只计本周会话的专注内暂停（次数 + 总时长）；
/// - 08-B3：中断按次数归入时段分布、中断占比与单次均值、最长连续段
///   （含所在时段）、最专注的一天、有记录天数；未闭合暂停只计次数；
/// - toUploadJson 为白名单序列化：新增字段默认不进上传体（07 §5.1）。
library;

import 'package:ai_clock/core/insight/insight_engine.dart';
import 'package:ai_clock/features/stats/domain/elastic_streak.dart';
import 'package:ai_clock/features/stats/domain/weekly_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 固定参考时刻：2026-08-26（周三）12:00 → 本周一 = 08-24，上周一 = 08-17
  final now = DateTime(2026, 8, 26, 12);
  final thisMonday = DateTime(2026, 8, 24);
  final lastMonday = DateTime(2026, 8, 17);

  InsightSessionFact session(
    DateTime day,
    int hour, {
    int focusMinutes = 25,
    int rounds = 1,
    List<(int, int?)> pauses = const [],
  }) {
    final start = DateTime(day.year, day.month, day.day, hour);
    return InsightSessionFact(
      startAtMillis: start.millisecondsSinceEpoch,
      focusMillis: focusMinutes * 60 * 1000,
      rounds: rounds,
      pauses: pauses,
    );
  }

  const noStreak = StreakResult(days: 0, bufferUsed: 0);

  group('buildWeeklyInsight', () {
    test('空周报：全部为零/空，环比 null', () {
      final insight = buildWeeklyInsight(
        sessions: const [],
        streak: noStreak,
        now: now,
      );
      expect(insight.thisWeekMinutes, 0);
      expect(insight.lastWeekMinutes, 0);
      expect(insight.changeRatio, isNull);
      expect(insight.sessionCount, 0);
      expect(insight.rounds, 0);
      expect(insight.slotDistribution, isEmpty);
      expect(insight.bestSlot, isNull);
      expect(insight.interruptionCount, 0);
      expect(insight.interruptionMinutes, 0);
    });

    test('环比为正：本周 620 分钟 vs 上周 540 分钟 ≈ +0.148', () {
      final insight = buildWeeklyInsight(
        sessions: [
          session(thisMonday, 9, focusMinutes: 620),
          session(lastMonday, 9, focusMinutes: 540),
        ],
        streak: noStreak,
        now: now,
      );
      expect(insight.thisWeekMinutes, 620);
      expect(insight.lastWeekMinutes, 540);
      expect(insight.changeRatio, closeTo(0.148, 0.001));
      expect(insight.sessionCount, 1);
    });

    test('环比为负：本周 300 分钟 vs 上周 600 分钟 = -0.5', () {
      final insight = buildWeeklyInsight(
        sessions: [
          session(thisMonday, 9, focusMinutes: 300),
          session(lastMonday, 9, focusMinutes: 600),
        ],
        streak: noStreak,
        now: now,
      );
      expect(insight.changeRatio, closeTo(-0.5, 0.001));
    });

    test('上周无基线：changeRatio 为 null 而非 +inf', () {
      final insight = buildWeeklyInsight(
        sessions: [session(thisMonday, 9, focusMinutes: 100)],
        streak: noStreak,
        now: now,
      );
      expect(insight.changeRatio, isNull);
    });

    test('时段四桶边界：0/6/12/18 点各归 凌晨/上午/下午/晚上', () {
      final insight = buildWeeklyInsight(
        sessions: [
          session(thisMonday, 0, focusMinutes: 10),
          session(thisMonday, 6, focusMinutes: 20),
          session(thisMonday, 12, focusMinutes: 30),
          session(thisMonday, 18, focusMinutes: 40),
        ],
        streak: noStreak,
        now: now,
      );
      expect(insight.slotDistribution[DaySlot.dawn], closeTo(0.1, 0.001));
      expect(insight.slotDistribution[DaySlot.morning], closeTo(0.2, 0.001));
      expect(insight.slotDistribution[DaySlot.afternoon], closeTo(0.3, 0.001));
      expect(insight.slotDistribution[DaySlot.evening], closeTo(0.4, 0.001));
      expect(insight.bestSlot, DaySlot.evening);
    });

    test('中断聚合：只计本周；闭合按时长、未闭合计次数不计时长', () {
      final t = DateTime(thisMonday.year, thisMonday.month, thisMonday.day, 9);
      final p1 = t.millisecondsSinceEpoch;
      final insight = buildWeeklyInsight(
        sessions: [
          session(thisMonday, 9, pauses: [
            (p1, p1 + 5 * 60 * 1000), // 闭合 5 分钟
            (p1 + 10 * 60 * 1000, null), // 未闭合：计次数不计时长
          ]),
          session(lastMonday, 9, pauses: [
            (p1, p1 + 60 * 60 * 1000), // 上周的中断不计入
          ]),
        ],
        streak: noStreak,
        now: now,
      );
      expect(insight.interruptionCount, 2);
      expect(insight.interruptionMinutes, 5);
    });

    test('弹性连续透传：streakDays/bufferUsed 来自输入', () {
      final insight = buildWeeklyInsight(
        sessions: [session(thisMonday, 9)],
        streak: const StreakResult(days: 5, bufferUsed: 1),
        now: now,
      );
      expect(insight.streakDays, 5);
      expect(insight.bufferUsed, 1);
    });

    test('上周同期口径：上周进度点之后的数据不计入基线（08-A1）', () {
      // now = 周三 12:00 → 上周基线只取到上周三 12:00（cutoff = 上周一 + 2d12h）
      final insight = buildWeeklyInsight(
        sessions: [
          session(thisMonday, 9, focusMinutes: 100), // 本周一
          session(lastMonday, 9, focusMinutes: 100), // 上周一：在同期窗口内
          session(lastMonday.add(const Duration(days: 4)), 9,
              focusMinutes: 500), // 上周五：已超出同期进度，不计
        ],
        streak: noStreak,
        now: now,
      );
      // 基线是 100 分钟（同期）而非 600 分钟（完整周），环比才是可比的
      expect(insight.lastWeekMinutes, 100);
      expect(insight.changeRatio, closeTo(0, 1e-9));
    });

    test('daysElapsed 与解读门槛：周三=3；25 分钟/1 次会话不足以解读（08-A1/A6）', () {
      final thin = buildWeeklyInsight(
        sessions: [session(thisMonday, 9, focusMinutes: 25)],
        streak: noStreak,
        now: now,
      );
      expect(thin.daysElapsed, 3);
      expect(thin.isSufficient, isFalse);

      // 够 3 次会话即放行
      final enough = buildWeeklyInsight(
        sessions: [
          session(thisMonday, 9, focusMinutes: 10),
          session(thisMonday, 14, focusMinutes: 10),
          session(thisMonday, 20, focusMinutes: 10),
        ],
        streak: noStreak,
        now: now,
      );
      expect(enough.isSufficient, isTrue);
    });

    test('数据指纹随汇总字段变化（08-A2）', () {
      final a = buildWeeklyInsight(
        sessions: [session(thisMonday, 9, focusMinutes: 25)],
        streak: noStreak,
        now: now,
      );
      final b = buildWeeklyInsight(
        sessions: [session(thisMonday, 9, focusMinutes: 50)],
        streak: noStreak,
        now: now,
      );
      expect(a.dataFingerprint, isNot(b.dataFingerprint));
      // 指纹不上传，只用于本地缓存比对
      expect(a.toUploadJson().containsKey('fp'), isFalse);
    });

    test('轮数只计本周', () {
      final insight = buildWeeklyInsight(
        sessions: [
          session(thisMonday, 9, rounds: 3),
          session(lastMonday, 9, rounds: 7),
        ],
        streak: noStreak,
        now: now,
      );
      expect(insight.rounds, 3);
    });

    // ------------------------------------------------ 08-B3：洞察字段扩充

    test('中断时段分布 / 占比 / 单次均值（按次数归桶）', () {
      const minute = 60 * 1000;
      final mon9 = DateTime(2026, 8, 24, 9).millisecondsSinceEpoch;
      final mon20 = DateTime(2026, 8, 24, 20).millisecondsSinceEpoch;
      final insight = buildWeeklyInsight(
        sessions: [
          // 上午 60 分钟，2 次中断（各 5 分钟）
          session(thisMonday, 9, focusMinutes: 60, pauses: [
            (mon9 + 10 * minute, mon9 + 15 * minute),
            (mon9 + 30 * minute, mon9 + 35 * minute),
          ]),
          // 晚上 40 分钟，1 次中断（10 分钟）
          session(thisMonday, 20, focusMinutes: 40, pauses: [
            (mon20 + 5 * minute, mon20 + 15 * minute),
          ]),
        ],
        streak: noStreak,
        now: now,
      );
      expect(insight.interruptionCount, 3);
      expect(insight.interruptionMinutes, 20);
      expect(insight.interruptionRatio, closeTo(0.2, 1e-9));
      expect(insight.avgInterruptionMinutes, 7); // 20 / 3 ≈ 6.67 → 7
      expect(insight.interruptionSlotDistribution[DaySlot.morning],
          closeTo(2 / 3, 1e-9));
      expect(insight.interruptionSlotDistribution[DaySlot.evening],
          closeTo(1 / 3, 1e-9));
    });

    test('最长段（含所在时段）/ 最专注的一天 / 有记录天数', () {
      final insight = buildWeeklyInsight(
        sessions: [
          session(thisMonday, 9, focusMinutes: 30),
          session(thisMonday, 20, focusMinutes: 90),
          session(DateTime(2026, 8, 26), 14, focusMinutes: 45), // 周三
        ],
        streak: noStreak,
        now: now,
      );
      expect(insight.longestSegmentMinutes, 90);
      expect(insight.longestSegmentSlot, DaySlot.evening);
      // 周一 120 分钟 vs 周三 45 分钟
      expect(insight.bestDayWeekday, 1);
      expect(insight.bestDayMinutes, 120);
      expect(insight.activeDays, 2);
    });

    test('未闭合暂停只计次数：不计时长、不进均值', () {
      const minute = 60 * 1000;
      final mon9 = DateTime(2026, 8, 24, 9).millisecondsSinceEpoch;
      final insight = buildWeeklyInsight(
        sessions: [
          session(thisMonday, 9, focusMinutes: 30, pauses: [
            (mon9 + 5 * minute, mon9 + 10 * minute),
            (mon9 + 20 * minute, null), // 结算时仍在暂停中
          ]),
        ],
        streak: noStreak,
        now: now,
      );
      expect(insight.interruptionCount, 2);
      expect(insight.interruptionMinutes, 5);
      expect(insight.avgInterruptionMinutes, 3); // 5 / 2 = 2.5 → 3
      // 两次都发生在上午
      expect(insight.interruptionSlotDistribution[DaySlot.morning], 1.0);
    });

    test('无会话：新字段全部为空/零/null（不编造）', () {
      final insight = buildWeeklyInsight(
        sessions: const [],
        streak: noStreak,
        now: now,
      );
      expect(insight.interruptionSlotDistribution, isEmpty);
      expect(insight.interruptionRatio, isNull);
      expect(insight.avgInterruptionMinutes, 0);
      expect(insight.longestSegmentMinutes, 0);
      expect(insight.longestSegmentSlot, isNull);
      expect(insight.bestDayWeekday, isNull);
      expect(insight.bestDayMinutes, 0);
      expect(insight.activeDays, 0);
    });
  });

  group('toUploadJson 白名单', () {
    test('字段恰好是白名单集合（新增字段默认不上传）', () {
      // 带一次中断：让中断相关字段全部出现（无中断时该组字段整体省略，
      // 不给 LLM 看空值干扰项）
      const minute = 60 * 1000;
      final mon9 = DateTime(2026, 8, 24, 9).millisecondsSinceEpoch;
      final insight = buildWeeklyInsight(
        sessions: [
          session(thisMonday, 9, focusMinutes: 620, rounds: 17, pauses: [
            (mon9 + 20 * minute, mon9 + 25 * minute),
          ]),
          session(lastMonday, 9, focusMinutes: 540),
        ],
        streak: const StreakResult(days: 5, bufferUsed: 1),
        now: now,
      );
      final json = insight.toUploadJson();
      expect(
        json.keys.toSet(),
        {
          'week_focus_minutes',
          'last_week_focus_minutes',
          'days_elapsed',
          'change_ratio',
          'session_count',
          'rounds',
          'slot_distribution',
          'streak_days',
          'buffer_used',
          'interruption_count',
          'interruption_minutes',
          // 08-B3 新增（全部为时段/时长聚合，无应用名或内容维度）
          'interruption_slot_distribution',
          'interruption_ratio',
          'avg_interruption_minutes',
          'longest_segment_minutes',
          'longest_segment_slot',
          'best_day_label',
          'best_day_minutes',
          'active_days',
        },
      );
      expect(json['week_focus_minutes'], 620);
      expect(json['last_week_focus_minutes'], 540);
      expect(json['rounds'], 17);
      expect(json['streak_days'], 5);
      // 部分周如实上传（08-A1）：now 是周三 → 已过 3 天
      expect(json['days_elapsed'], 3);
      // 数据指纹只用于本地比对，不得出设备（08-A2）
      expect(json.containsKey('fp'), isFalse);
      // 时段分布用中文标签（prompt 直接可读），无枚举名泄漏
      final slots = json['slot_distribution'] as Map<String, dynamic>;
      expect(slots.keys, contains('上午'));
      // 08-B3：新增字段同样用中文标签、值可核对
      expect(json['longest_segment_minutes'], 620);
      expect(json['longest_segment_slot'], '上午');
      expect(json['best_day_label'], '周一');
      expect(json['best_day_minutes'], 620);
      expect(json['active_days'], 1);
      expect(json['avg_interruption_minutes'], 5);
      final intSlots =
          json['interruption_slot_distribution'] as Map<String, dynamic>;
      expect(intSlots.keys, contains('上午'));
    });

    test('环比 null 时上传体省略 change_ratio 字段（不误导）', () {
      final insight = buildWeeklyInsight(
        sessions: [session(thisMonday, 9)],
        streak: noStreak,
        now: now,
      );
      expect(insight.toUploadJson().containsKey('change_ratio'), isFalse);
    });

    test('脏数据扫描：上传体不含应用名/设备标识样式串', () {
      final insight = buildWeeklyInsight(
        sessions: [session(thisMonday, 9)],
        streak: noStreak,
        now: now,
      );
      final raw = insight.toUploadJson().toString();
      // 白名单字段都是数字与中文时段标签，不应出现包名/ID 样式内容
      expect(raw, isNot(contains('com.')));
      expect(raw, isNot(contains('imei')));
      expect(raw, isNot(contains('android_id')));
    });
  });
}
