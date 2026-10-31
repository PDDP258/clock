/// 专注时段记录构建器（纯 Dart，可单测）：把引擎状态折算为落库记录。
///
/// 诚实统计（真机反馈 R1 起）：番茄模式「跳过专注」不计完成轮数，
/// 只把真实已做部分计入引擎的 accumulatedFocusMillis；本构建器不再做
/// 「轮数×整轮」折算，直接以引擎累计为准，叠加进行中当前轮的已做部分。
library;

import 'timer_engine.dart';
import 'timer_mode.dart';

/// 专注时段记录（落库前的纯数据快照，对应 drift focus_session 表）。
class FocusSessionRecord {
  const FocusSessionRecord({
    required this.mode,
    required this.startAtMillis,
    required this.endAtMillis,
    required this.plannedFocusMillis,
    required this.actualFocusMillis,
    required this.rounds,
    required this.completed,
    this.marks = const <Duration>[],
    this.focusSegments = const <(int, int)>[],
    this.pauses = const <(int, int?)>[],
  });

  /// 计时模式
  final TimerMode mode;

  /// 会话开始墙上时间戳（毫秒）
  final int startAtMillis;

  /// 会话结束墙上时间戳（毫秒）
  final int endAtMillis;

  /// 计划专注总毫秒（正计时不限时 = 0）
  final int plannedFocusMillis;

  /// 实际专注总毫秒（扣除暂停/休息）
  final int actualFocusMillis;

  /// 完成轮数（正计时 = 0）
  final int rounds;

  /// 是否正常结束（用户主动 finish = true；崩溃结算等异常路径 = false）
  final bool completed;

  /// 正计时打点（相对开始的偏移），US-B02 复盘用；番茄模式恒为空
  final List<Duration> marks;

  /// 各专注段的实际墙钟区间（startMillis, endMillis），供时间轴
  /// 「断断续续 + 休息空隙」渲染（R8）。休息段不入列，空隙即休息。
  final List<(int, int)> focusSegments;

  /// 专注阶段内的暂停（中断）区间（startMillis, endMillis?），US-D02。
  /// 进行中的暂停 endMillis 为 null（结算快照时刻仍在暂停）。
  final List<(int, int?)> pauses;
}

/// 由引擎快照构建落库记录。
abstract final class SessionRecordBuilder {
  /// 番茄模式：实际专注 = 引擎真实累计 + 进行中专注段的已计部分。
  ///
  /// [accumulatedFocusMillis] 来自引擎：自然完成与跳过都按实际段长入账。
  /// [currentFocusDoneMillis] 是进行中专注段的真实已做毫秒（引擎以
  /// 「段开始时间戳 - 段内暂停」计算，R9；addTime 加时不被吞、暂停不计）；
  /// 「待继续」（新段未开始）与休息阶段为 0，不计入。
  /// [currentFocusStartedAtMillis] 为进行中段的开始时间戳（时间轴末段用；
  /// null 时按 endAt - done 回推）。
  /// 实际专注为 0（刚开始就结束）→ 返回 null（不落库，避免污染统计）。
  /// [completed]=false 用于进行中结算（R3 每轮/暂停结算，endAt 由落库层置 null）。
  /// [focusSegments] 为引擎已记录的各专注段区间；进行中专注段的已做
  /// 部分会作为末段自动补上（段终点由 [activeFocusEndMillis] 决定）。
  /// [activeFocusEndMillis] 为进行中专注段的**实际结束时刻**：正常运行
  /// 即 [endAtMillis]（当前时刻）；恢复冻结/跨天冲刷等场景 [endAtMillis]
  /// 是「重开进程的时刻」，若直接拿它当段终点，会把一段半小时的专注在
  /// 时间轴上拉成跨越关机的大块（真机反馈 R12）。传 null 时回退 [endAtMillis]。
  static FocusSessionRecord? fromPomodoro({
    required int startAtMillis,
    required int endAtMillis,
    required int completedRounds,
    required int accumulatedFocusMillis,
    required PomodoroConfig config,
    required TimerPhase phase,
    required TimerPhase? phaseBeforePause,
    required int currentFocusDoneMillis,
    int? currentFocusStartedAtMillis,
    int? activeFocusEndMillis,
    List<(int, int)> focusSegments = const <(int, int)>[],
    List<(int, int?)> pauses = const <(int, int?)>[],
    bool completed = true,
  }) {
    final focusMillis = config.focusDuration.inMilliseconds;
    var actual = accumulatedFocusMillis;
    final segments = List<(int, int)>.of(focusSegments);

    final inFocus = phase == TimerPhase.focusing ||
        (phase == TimerPhase.paused &&
            phaseBeforePause == TimerPhase.focusing);
    // 进行中且真实已做 >0 才计入：待继续（done=0）不算一轮、不占计划
    final inProgress = inFocus && currentFocusDoneMillis > 0;
    if (inProgress) {
      actual += currentFocusDoneMillis;
      final segStart =
          currentFocusStartedAtMillis ?? endAtMillis - currentFocusDoneMillis;
      var segEnd = activeFocusEndMillis ?? endAtMillis;
      if (segEnd < segStart) segEnd = segStart;
      segments.add((segStart, segEnd));
    }
    if (actual <= 0) return null;

    return FocusSessionRecord(
      mode: TimerMode.pomodoro,
      startAtMillis: startAtMillis,
      endAtMillis: endAtMillis,
      plannedFocusMillis: focusMillis * (completedRounds + (inProgress ? 1 : 0)),
      actualFocusMillis: actual,
      rounds: completedRounds,
      completed: completed,
      focusSegments: segments,
      pauses: pauses,
    );
  }

  /// 正计时模式：elapsed 即实际专注；planned=0（不限时）、rounds=0；
  /// 打点 [marks] 随记录保存（US-B02 复盘）。0 秒直接结束 → 返回 null（不落库）。
  /// [completed]=false 用于进行中结算（R3 每轮/暂停结算，endAt 由落库层置 null）。
  /// [activeFocusEndMillis] 为专注段的实际结束时刻（暂停中即最后一次活动时刻）——
  /// 运行时等于 [endAtMillis]；恢复冻结/跨天冲刷时 [endAtMillis] 是重开时刻，
  /// 用它渲染段会把一段专注拉成跨越关机的大块（R12）。null 回退 [endAtMillis]。
  static FocusSessionRecord? fromCountUp({
    required int startAtMillis,
    required int endAtMillis,
    required Duration elapsed,
    int? activeFocusEndMillis,
    List<Duration> marks = const <Duration>[],
    List<(int, int?)> pauses = const <(int, int?)>[],
    bool completed = true,
  }) {
    if (elapsed.inMilliseconds <= 0) return null;
    var segEnd = activeFocusEndMillis ?? endAtMillis;
    if (segEnd < startAtMillis) segEnd = startAtMillis;
    return FocusSessionRecord(
      mode: TimerMode.countUp,
      startAtMillis: startAtMillis,
      endAtMillis: endAtMillis,
      plannedFocusMillis: 0,
      actualFocusMillis: elapsed.inMilliseconds,
      rounds: 0,
      completed: completed,
      marks: marks,
      // 正计时天然连续：一整段即全部专注区间
      focusSegments: <(int, int)>[(startAtMillis, segEnd)],
      pauses: pauses,
    );
  }
}
