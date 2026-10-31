// 暂停态的阶段色归属（PD 2026-10-07 真机反馈：暂停时颜色闪成休息色再跳回）
//
// 背景：`paused` 原先在 UI 层被当成一个独立阶段取色（走 accentColor 分支），
// 且时钟交叉淡化的起点色只在「颜色变化时」写、从不清理——于是下一次转场
// （暂停/继续这类颜色并未变化的转场）会拿陈旧色当淡化起点，闪一下。
//
// 这里钉住的语义：**暂停是「冻结」不是「换段」**——颜色沿用暂停前那一段。
library;

import 'package:ai_clock/core/timer/count_up_timer.dart';
import 'package:ai_clock/core/timer/timer_engine.dart';
import 'package:ai_clock/core/timer/timer_mode.dart';
import 'package:ai_clock/features/focus/application/focus_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个只关心阶段字段的视图状态。
FocusViewState build({
  required TimerPhase phase,
  TimerPhase? phaseBeforePause,
}) {
  return FocusViewState(
    mode: TimerMode.pomodoro,
    phase: phase,
    phaseBeforePause: phaseBeforePause,
    remaining: const Duration(minutes: 5),
    phaseTotal: const Duration(minutes: 25),
    completedRounds: 0,
    countUpPhase: CountUpPhase.idle,
    elapsed: Duration.zero,
    markCount: 0,
    keysAcquired: false,
    lastCommand: null,
  );
}

void main() {
  group('FocusViewState.colorPhase', () {
    test('专注中：colorPhase 就是专注', () {
      expect(
        build(phase: TimerPhase.focusing).colorPhase,
        TimerPhase.focusing,
      );
    });

    test('短休中：colorPhase 就是短休', () {
      expect(
        build(phase: TimerPhase.shortBreak).colorPhase,
        TimerPhase.shortBreak,
      );
    });

    test('专注中暂停：沿用专注色（不跳去休息色）', () {
      expect(
        build(
          phase: TimerPhase.paused,
          phaseBeforePause: TimerPhase.focusing,
        ).colorPhase,
        TimerPhase.focusing,
      );
    });

    test('休息中暂停：沿用休息色（不被硬编码成专注色）', () {
      expect(
        build(
          phase: TimerPhase.paused,
          phaseBeforePause: TimerPhase.longBreak,
        ).colorPhase,
        TimerPhase.longBreak,
      );
    });

    test('暂停但引擎没记住原阶段：退回 paused，UI 侧再兜到专注色', () {
      // 引擎记忆丢失属于「不该发生」，但 colorPhase 不得抛异常，
      // 也不能凭空给出休息色。
      expect(
        build(phase: TimerPhase.paused).colorPhase,
        TimerPhase.paused,
      );
    });

    test('暂停 → 继续：颜色相位回到原阶段，两端一致（暂停不改色）', () {
      const before = TimerPhase.focusing;
      final paused = build(
        phase: TimerPhase.paused,
        phaseBeforePause: before,
      );
      final resumed = build(phase: TimerPhase.focusing);
      // 关键性质：暂停与继续解析出同一个阶段色 —— 颜色不发生任何变化，
      // 因此时钟不该播交叉淡化（否则会闪出陈旧色）。
      expect(paused.colorPhase, resumed.colorPhase);
    });
  });

  group('引擎的 phaseBeforePause 与 colorPhase 口径一致', () {
    test('专注暂停 → phaseBeforePause=focusing，colorPhase=focusing', () {
      final engine = TimerEngine(config: _config());
      engine.start();
      expect(engine.phase, TimerPhase.focusing);
      engine.pause();
      expect(engine.phase, TimerPhase.paused);
      expect(engine.phaseBeforePause, TimerPhase.focusing);

      final view = build(
        phase: engine.phase,
        phaseBeforePause: engine.phaseBeforePause,
      );
      expect(view.colorPhase, TimerPhase.focusing);
    });

    test('继续后 phaseBeforePause 清空，colorPhase 仍是专注', () {
      final engine = TimerEngine(config: _config());
      engine.start();
      engine.pause();
      engine.resume();
      expect(engine.phase, TimerPhase.focusing);
      expect(engine.phaseBeforePause, isNull);

      final view = build(
        phase: engine.phase,
        phaseBeforePause: engine.phaseBeforePause,
      );
      expect(view.colorPhase, TimerPhase.focusing);
    });
  });
}

/// 25 分钟专注 / 5 分钟短休 / 15 分钟长休，4 轮一长休。
PomodoroConfig _config() => const PomodoroConfig(
      focusDuration: Duration(minutes: 25),
      shortBreakDuration: Duration(minutes: 5),
      longBreakDuration: Duration(minutes: 15),
      roundsBeforeLongBreak: 4,
    );
