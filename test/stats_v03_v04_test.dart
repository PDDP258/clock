/// V0.3/V0.4 统计用例：中断记录（US-D02）、弹性连续（US-D03）、周报（US-D04）。
///
/// 引擎暂停记录走假时钟精确控制；统计算法均为纯函数。
library;

import 'dart:convert';

import 'package:ai_clock/core/timer/count_up_timer.dart';
import 'package:ai_clock/core/timer/timer_engine.dart';
import 'package:ai_clock/features/stats/domain/elastic_streak.dart';
import 'package:ai_clock/features/stats/domain/focus_interruption.dart';
import 'package:ai_clock/features/stats/domain/weekly_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假时钟：测试手动推进。
class FakeClock {
  DateTime _now = DateTime(2024, 1, 1, 8);

  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);
}

PomodoroConfig _testConfig() => const PomodoroConfig(
      focusDuration: Duration(seconds: 100),
      shortBreakDuration: Duration(seconds: 20),
      longBreakDuration: Duration(seconds: 50),
      roundsBeforeLongBreak: 4,
      autoContinue: true,
    );

void main() {
  group('番茄引擎中断记录（US-D02）', () {
    late FakeClock clock;
    late TimerEngine engine;

    setUp(() {
      clock = FakeClock();
      engine = TimerEngine(config: _testConfig(), clock: clock.now);
    });

    test('专注中暂停记入中断，恢复后闭合', () {
      engine.start();
      clock.advance(const Duration(seconds: 30));
      engine.pause();
      expect(engine.pauses.length, 1);
      expect(engine.pauses.last.$2, isNull); // 暂停中：未闭合

      clock.advance(const Duration(seconds: 10));
      engine.resume();
      expect(engine.pauses.last.$2, isNotNull);
      // 中断跨度 = 暂停的 10 秒
      final (start, end) = engine.pauses.last;
      expect(end! - start, const Duration(seconds: 10).inMilliseconds);
    });

    test('休息阶段暂停不算中断', () {
      engine.start();
      clock.advance(const Duration(seconds: 100)); // 专注自然结束→短休
      engine.tick();
      expect(engine.phase, TimerPhase.shortBreak);
      engine.pause();
      expect(engine.pauses, isEmpty);
    });

    test('暂停中跳过/结束都会闭合中断；JSON 往返保留', () {
      engine.start();
      clock.advance(const Duration(seconds: 30));
      engine.pause();
      engine.skipPhase(); // 暂停中跳过专注
      expect(engine.pauses.last.$2, isNotNull);

      engine.resume(); // 进入休息……不对：跳过后在休息态，resume 无效
      engine.pause(); // 休息暂停不记
      expect(engine.pauses.length, 1);

      // JSON 往返
      final restored =
          TimerEngine.fromJson(engine.toJson(), clock: clock.now);
      expect(restored.pauses.length, 1);
      expect(restored.pauses.last.$1, engine.pauses.last.$1);
      expect(restored.pauses.last.$2, engine.pauses.last.$2);
    });

    test('新会话/复位清空中断记录', () {
      engine.start();
      clock.advance(const Duration(seconds: 30));
      engine.pause();
      engine.finish(); // 暂停中结束：闭合
      expect(engine.pauses.last.$2, isNotNull);

      engine.start(); // 新会话
      expect(engine.pauses, isEmpty);
    });
  });

  group('正计时中断记录（US-D02）', () {
    late FakeClock clock;
    late CountUpTimer timer;

    setUp(() {
      clock = FakeClock();
      timer = CountUpTimer(clock: clock.now);
    });

    test('暂停/恢复各记一次闭合中断；暂停中结束按结束时刻闭合', () {
      timer.start();
      clock.advance(const Duration(minutes: 10));
      timer.pause();
      clock.advance(const Duration(minutes: 2));
      timer.resume();
      clock.advance(const Duration(minutes: 5));
      timer.pause();
      clock.advance(const Duration(minutes: 1));
      timer.finish(); // 暂停中结束

      expect(timer.pauses.length, 2);
      final (s1, e1) = timer.pauses[0];
      expect(e1! - s1, const Duration(minutes: 2).inMilliseconds);
      final (s2, e2) = timer.pauses[1];
      expect(e2! - s2, const Duration(minutes: 1).inMilliseconds);

      final restored = CountUpTimer.fromJson(timer.toJson(), clock: clock.now);
      expect(restored.pauses.length, 2);
    });
  });

  group('中断解析 parseInterruptions', () {
    test('null/空串/损坏 JSON → 空列表', () {
      expect(parseInterruptions(null), isEmpty);
      expect(parseInterruptions(''), isEmpty);
      expect(parseInterruptions('not-json{'), isEmpty);
    });

    test('正常解析，进行中的暂停 end 为 null', () {
      final json = jsonEncode([
        [1000, 2000],
        [3000, null],
      ]);
      final result = parseInterruptions(json);
      expect(result, [(1000, 2000), (3000, null)]);
    });
  });

  group('打点解析 parseMarks（US-B02 时间轴刻度）', () {
    test('null/空串/损坏 JSON → 空列表', () {
      expect(parseMarks(null), isEmpty);
      expect(parseMarks(''), isEmpty);
      expect(parseMarks('not-json{'), isEmpty);
    });

    test('正常解析为偏移毫秒并升序排序', () {
      final json = jsonEncode([900000, 60000, 300000]);
      expect(parseMarks(json), [60000, 300000, 900000]);
    });
  });

  group('弹性连续 elasticStreak（US-D03）', () {
    final now = DateTime(2026, 8, 4, 15); // 周二
    int day(int offset) => DateTime(2026, 8, 4 + offset).millisecondsSinceEpoch;

    test('完全无数据 → 连续 0 天', () {
      final r = elasticStreak({}, now);
      expect(r.days, 0);
      expect(r.bufferUsed, 0);
    });

    test('连续 3 天（含今天）', () {
      final r = elasticStreak({day(0), day(-1), day(-2)}, now);
      expect(r.days, 3);
      expect(r.bufferUsed, 0);
    });

    test('今天还没专注不破坏连续（锚定昨天）', () {
      final r = elasticStreak({day(-1), day(-2)}, now);
      expect(r.days, 2);
    });

    test('每周 2 天缓冲：缺 2 天不断，缺第 3 天断开', () {
      // 今天有，缺昨天/前天，再往前连续 → 链条含 2 缓冲日
      final r = elasticStreak({day(0), day(-3), day(-4)}, now);
      expect(r.days, 5); // 今天 + 2 缓冲 + 2 专注
      expect(r.bufferUsed, 2);

      // 7 天窗口内缺 3 天 → 断开
      final r2 = elasticStreak({day(0), day(-4)}, now);
      expect(r2.days, 1); // 只剩今天（-1/-2/-3 三天缺勤超缓冲）
    });

    test('断签不清零：老链条被缓冲规则切断后，新链条从最近专注日起算', () {
      // 上周连续 5 天，本周只今天 → 昨天/前天吃缓冲，大前天第 3 个缺勤断开；
      // 连续天数锚在链条内最老专注日（=今天），尾部缓冲日不吹进天数
      final r = elasticStreak(
          {day(0), day(-7), day(-8), day(-9), day(-10), day(-11)}, now);
      expect(r.days, 1);
      expect(r.bufferUsed, 0); // 缺勤日在跨度（今天）之外，不计入
    });
  });

  group('每周报告 buildWeeklyReport（US-D04）', () {
    // 2026-08-04 是周二；本周一 = 08-03，上周一 = 07-27
    final now = DateTime(2026, 8, 4, 15);
    int at(int month, int day, int hour) =>
        DateTime(2026, month, day, hour).millisecondsSinceEpoch;

    test('本周/上周同期分桶与环比', () {
      final r = buildWeeklyReport([
        (at(8, 3, 9), 1000), // 本周一 上午
        (at(8, 4, 14), 3000), // 本周二 下午
        (at(7, 28, 10), 2000), // 上周二 15:00 之前（同期窗口内）
      ], now);
      expect(r.thisWeekMillis, 4000);
      expect(r.lastWeekMillis, 2000);
      expect(r.changeRatio, closeTo(1.0, 1e-9)); // +100%
      expect(r.daysElapsed, 2); // 周二
    });

    test('环比只取上周同期进度（08-A1：部分周不再被压成假退步）', () {
      final r = buildWeeklyReport([
        (at(8, 3, 9), 1000),
        (at(8, 4, 14), 3000),
        // 上周同期（周一、周二 15:00 之前）共 4000
        (at(7, 27, 9), 1000),
        (at(7, 28, 14), 3000),
        // 上周四：超出本周已过进度，若计入就会把环比压成假退步
        (at(7, 30, 10), 5000),
      ], now);
      expect(r.thisWeekMillis, 4000);
      expect(r.lastWeekMillis, 4000, reason: '基线应不含上周四的 5000');
      expect(r.changeRatio, closeTo(0, 1e-9));
    });

    test('上周无数据 → 环比为 null（无基线不误导）', () {
      final r = buildWeeklyReport([(at(8, 4, 9), 1000)], now);
      expect(r.changeRatio, isNull);
      expect(r.bestSlot, DaySlot.morning);
    });

    test('最专注时段取四桶最大值；时段边界正确', () {
      expect(slotOfHour(5), DaySlot.dawn);
      expect(slotOfHour(6), DaySlot.morning);
      expect(slotOfHour(11), DaySlot.morning);
      expect(slotOfHour(12), DaySlot.afternoon);
      expect(slotOfHour(18), DaySlot.evening);
      expect(slotOfHour(23), DaySlot.evening);

      final r = buildWeeklyReport([
        (at(8, 3, 9), 1000),
        (at(8, 4, 20), 5000), // 晚上最多
      ], now);
      expect(r.bestSlot, DaySlot.evening);
      expect(r.bestSlotMillis, 5000);
    });

    test('本周无数据 → bestSlot 为 null', () {
      final r = buildWeeklyReport([(at(7, 30, 10), 2000)], now);
      expect(r.thisWeekMillis, 0);
      expect(r.bestSlot, isNull);
    });
  });
}
