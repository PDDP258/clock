/// 专注时段记录构建器单测（US-D01 数据闭环的纯 Dart 接缝）。
///
/// 语义要点：
/// - 实际专注为 0（刚开始就结束）不落库，避免污染统计；
/// - 番茄模式实际专注 = 引擎累计的真实专注（自然完成整轮 / 跳过只计已做部分）
///   + 进行中专注段的已计部分（含「专注中暂停」的冻结部分）；
/// - 跳过专注不计完成轮数（诚实统计，真机反馈 R1 修复）；
/// - 正计时 planned=0（不限时）、rounds=0，elapsed 即实际专注。
library;

import 'package:ai_clock/core/timer/session_record.dart';
import 'package:ai_clock/core/timer/timer_engine.dart';
import 'package:ai_clock/core/timer/timer_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = PomodoroConfig(); // 25/5/15, 4 轮长休

  group('SessionRecordBuilder.fromPomodoro', () {
    test('刚开始就结束：实际专注为 0，不落库', () {
      final record = SessionRecordBuilder.fromPomodoro(
        startAtMillis: 1000,
        endAtMillis: 2000,
        completedRounds: 0,
        accumulatedFocusMillis: 0,
        config: config,
        phase: TimerPhase.focusing,
        phaseBeforePause: null,
        currentFocusDoneMillis: 0, // 一秒未做
      );
      expect(record, isNull);
    });

    test('完成 2 轮 + 当前轮已做 15 分钟：actual = 65 分钟', () {
      final record = SessionRecordBuilder.fromPomodoro(
        startAtMillis: 1000,
        endAtMillis: 2000,
        completedRounds: 2,
        accumulatedFocusMillis: const Duration(minutes: 50).inMilliseconds,
        config: config,
        phase: TimerPhase.focusing,
        phaseBeforePause: null,
        currentFocusDoneMillis: const Duration(minutes: 15).inMilliseconds,
      );
      expect(record, isNotNull);
      expect(record!.actualFocusMillis, const Duration(minutes: 65).inMilliseconds);
      expect(record.plannedFocusMillis, const Duration(minutes: 75).inMilliseconds);
      expect(record.rounds, 2);
      expect(record.mode, TimerMode.pomodoro);
      expect(record.completed, isTrue);
    });

    test('专注中暂停：冻结的已做部分计入（已做 20 分钟）', () {
      final record = SessionRecordBuilder.fromPomodoro(
        startAtMillis: 1000,
        endAtMillis: 2000,
        completedRounds: 0,
        accumulatedFocusMillis: 0,
        config: config,
        phase: TimerPhase.paused,
        phaseBeforePause: TimerPhase.focusing,
        currentFocusDoneMillis: const Duration(minutes: 20).inMilliseconds,
      );
      expect(record!.actualFocusMillis, const Duration(minutes: 20).inMilliseconds);
    });

    test('休息中结束：只算完成轮数，不计休息部分', () {
      final record = SessionRecordBuilder.fromPomodoro(
        startAtMillis: 1000,
        endAtMillis: 2000,
        completedRounds: 1,
        accumulatedFocusMillis: const Duration(minutes: 25).inMilliseconds,
        config: config,
        phase: TimerPhase.shortBreak,
        phaseBeforePause: null,
        currentFocusDoneMillis: 0, // 休息阶段无进行中专注段
      );
      expect(record!.actualFocusMillis, const Duration(minutes: 25).inMilliseconds);
      // 休息中暂停不应误判为专注中暂停
      final pausedBreak = SessionRecordBuilder.fromPomodoro(
        startAtMillis: 1000,
        endAtMillis: 2000,
        completedRounds: 1,
        accumulatedFocusMillis: const Duration(minutes: 25).inMilliseconds,
        config: config,
        phase: TimerPhase.paused,
        phaseBeforePause: TimerPhase.shortBreak,
        currentFocusDoneMillis: 0,
      );
      expect(pausedBreak!.actualFocusMillis, const Duration(minutes: 25).inMilliseconds);
    });

    test('跳过专注的会话：只累计真实已做部分，轮数为 0（真机反馈 R1）', () {
      // 引擎行为：跳过 25 分钟轮的 3 分钟处 → accumulated=3min、rounds=0、
      // 当前处于短休。落库必须如实反映，不得折算成整轮。
      final record = SessionRecordBuilder.fromPomodoro(
        startAtMillis: 1000,
        endAtMillis: 2000,
        completedRounds: 0,
        accumulatedFocusMillis: const Duration(minutes: 3).inMilliseconds,
        config: config,
        phase: TimerPhase.shortBreak,
        phaseBeforePause: null,
        currentFocusDoneMillis: 0,
      );
      expect(record, isNotNull);
      expect(record!.actualFocusMillis, const Duration(minutes: 3).inMilliseconds);
      expect(record.rounds, 0);
    });

    test('待继续（轮结束等新段）：done=0 且无累计 → 不落库、不计轮（R9）', () {
      final record = SessionRecordBuilder.fromPomodoro(
        startAtMillis: 1000,
        endAtMillis: 2000,
        completedRounds: 1,
        accumulatedFocusMillis: const Duration(minutes: 25).inMilliseconds,
        config: config,
        phase: TimerPhase.paused,
        phaseBeforePause: TimerPhase.focusing,
        currentFocusDoneMillis: 0, // 新段未开始
      );
      // 已完成的 1 轮如实入账；未开始的新段既不加 actual 也不加 planned
      expect(record!.actualFocusMillis, const Duration(minutes: 25).inMilliseconds);
      expect(record.plannedFocusMillis, const Duration(minutes: 25).inMilliseconds);
      expect(record.rounds, 1);
    });

    test('进行中段带开始时间戳：末段区间用真实起点（时间轴 R8/R9）', () {
      const startedAt = 100000;
      const done = 15 * 60 * 1000; // 15 分钟
      final record = SessionRecordBuilder.fromPomodoro(
        startAtMillis: startedAt,
        endAtMillis: startedAt + done,
        completedRounds: 0,
        accumulatedFocusMillis: 0,
        config: config,
        phase: TimerPhase.focusing,
        phaseBeforePause: null,
        currentFocusDoneMillis: done,
        currentFocusStartedAtMillis: startedAt,
      );
      expect(record!.focusSegments.single, (startedAt, startedAt + done));
    });

    test('进行中结算：completed=false 透传（R3/R4 实时入账，endAt 由落库层置 null）', () {
      final record = SessionRecordBuilder.fromPomodoro(
        startAtMillis: 1000,
        endAtMillis: 2000,
        completedRounds: 1,
        accumulatedFocusMillis: const Duration(minutes: 25).inMilliseconds,
        config: config,
        phase: TimerPhase.shortBreak,
        phaseBeforePause: null,
        currentFocusDoneMillis: 0,
        completed: false,
      );
      expect(record, isNotNull);
      expect(record!.completed, isFalse);
      expect(record.actualFocusMillis, const Duration(minutes: 25).inMilliseconds);
    });

    test('恢复冻结/跨天冲刷：末段终点取实际活动时刻，不用重开时刻（R12）', () {
      const start = 100000;
      const done = 30 * 60 * 1000; // 已专注 30 分钟
      const pauseAt = start + done; // 21:30 开始，22:00 暂停
      const reopenAt = pauseAt + 13 * 3600 * 1000; // 次日 11:41 才开机
      final record = SessionRecordBuilder.fromPomodoro(
        startAtMillis: start,
        endAtMillis: reopenAt,
        completedRounds: 0,
        accumulatedFocusMillis: 0,
        config: config,
        phase: TimerPhase.paused,
        phaseBeforePause: TimerPhase.focusing,
        currentFocusDoneMillis: done,
        currentFocusStartedAtMillis: start,
        activeFocusEndMillis: pauseAt,
      );
      expect(record!.actualFocusMillis, done);
      // 段终点必须是暂停时刻，而不是重开时刻（旧实现会画成跨越关机的大块）
      expect(record.focusSegments.single, (start, pauseAt));
    });

    test('未传 activeFocusEndMillis：末段终点回退 endAt（兼容旧行为）', () {
      const start = 100000;
      const done = 15 * 60 * 1000;
      final record = SessionRecordBuilder.fromPomodoro(
        startAtMillis: start,
        endAtMillis: start + done,
        completedRounds: 0,
        accumulatedFocusMillis: 0,
        config: config,
        phase: TimerPhase.focusing,
        phaseBeforePause: null,
        currentFocusDoneMillis: done,
        currentFocusStartedAtMillis: start,
      );
      expect(record!.focusSegments.single, (start, start + done));
    });
  });

  group('SessionRecordBuilder.fromCountUp', () {
    test('elapsed 即实际专注；planned=0、rounds=0', () {
      final record = SessionRecordBuilder.fromCountUp(
        startAtMillis: 1000,
        endAtMillis: 2000,
        elapsed: const Duration(minutes: 47),
      );
      expect(record, isNotNull);
      expect(record!.mode, TimerMode.countUp);
      expect(record.actualFocusMillis, const Duration(minutes: 47).inMilliseconds);
      expect(record.plannedFocusMillis, 0);
      expect(record.rounds, 0);
      expect(record.completed, isTrue);
    });

    test('0 秒正计时直接结束：不落库', () {
      final record = SessionRecordBuilder.fromCountUp(
        startAtMillis: 1000,
        endAtMillis: 2000,
        elapsed: Duration.zero,
      );
      expect(record, isNull);
    });

    test('打点随记录保存（US-B02 复盘）；番茄模式恒为空', () {
      final record = SessionRecordBuilder.fromCountUp(
        startAtMillis: 1000,
        endAtMillis: 2000,
        elapsed: const Duration(minutes: 47),
        marks: const [Duration(minutes: 10), Duration(minutes: 32)],
      );
      expect(record!.marks, hasLength(2));
      expect(record.marks.last, const Duration(minutes: 32));

      final pomodoro = SessionRecordBuilder.fromPomodoro(
        startAtMillis: 1000,
        endAtMillis: 2000,
        completedRounds: 1,
        accumulatedFocusMillis: const Duration(minutes: 25).inMilliseconds,
        config: config,
        phase: TimerPhase.shortBreak,
        phaseBeforePause: null,
        currentFocusDoneMillis: 0,
      );
      expect(pomodoro!.marks, isEmpty);
    });

    test('恢复冻结：段终点取暂停时刻，不用重开时刻（R12）', () {
      const start = 100000;
      const elapsed = 30 * 60 * 1000;
      const pauseAt = start + elapsed;
      const reopenAt = pauseAt + 13 * 3600 * 1000;
      final record = SessionRecordBuilder.fromCountUp(
        startAtMillis: start,
        endAtMillis: reopenAt,
        elapsed: const Duration(minutes: 30),
        activeFocusEndMillis: pauseAt,
      );
      expect(record!.actualFocusMillis, elapsed);
      expect(record.focusSegments.single, (start, pauseAt));
    });
  });
}
