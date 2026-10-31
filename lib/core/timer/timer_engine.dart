/// 番茄钟计时引擎（纯 Dart，不 import 任何 Flutter 包，可独立单元测试）。
///
/// 设计要点：
/// 1. 剩余时间一律用「结束时间戳 - 当前时间戳」的差值计算，
///    绝不使用每秒累加的 Timer —— 累加计时在设备休眠、后台挂起、
///    进程被杀后会严重漂移；时间戳差值天然免疫这些问题。
/// 2. 状态可整体序列化为 JSON 持久化（墙上时钟时间戳）。App 被杀重启后
///    用 [TimerEngine.fromJson] 恢复，进程死亡期间流逝的时间会在下一次
///    [tick] 时自动补齐并触发阶段轮转。
/// 3. 引擎自身不创建任何 Timer，由上层（FocusController）周期性调用
///    [tick] 驱动轮转；测试时通过 [clock] 注入假时钟。
library;

/// 计时阶段状态机。
enum TimerPhase {
  /// 空闲，未开始
  idle,

  /// 专注中
  focusing,

  /// 已暂停（可暂停于专注或休息阶段，通过 [_phaseBeforePause] 记忆原阶段）
  paused,

  /// 短休息
  shortBreak,

  /// 长休息
  longBreak,

  /// 本次番茄会话已结束（用户主动结束）
  completed,
}

/// 阶段中文展示名（页面与通知共用，避免文案漂移）。
extension TimerPhaseX on TimerPhase {
  /// 展示名
  String get label => switch (this) {
        TimerPhase.idle => '准备开始',
        TimerPhase.focusing => '专注中',
        TimerPhase.paused => '已暂停',
        TimerPhase.shortBreak => '短休息',
        TimerPhase.longBreak => '长休息',
        TimerPhase.completed => '已完成',
      };
}

/// 番茄钟配置：默认专注 25 分钟 / 短休 5 分钟 / 长休 15 分钟 / 每 4 轮一次长休。
class PomodoroConfig {
  const PomodoroConfig({
    this.focusDuration = const Duration(minutes: 25),
    this.shortBreakDuration = const Duration(minutes: 5),
    this.longBreakDuration = const Duration(minutes: 15),
    this.roundsBeforeLongBreak = 4,
    this.autoContinue = false,
  });

  /// 单轮专注时长
  final Duration focusDuration;

  /// 短休息时长
  final Duration shortBreakDuration;

  /// 长休息时长
  final Duration longBreakDuration;

  /// 每完成多少轮专注后进入长休息
  final int roundsBeforeLongBreak;

  /// 休息结束是否自动开始下一段专注（真机反馈 R4）。
  /// 默认 false：一轮（专注+休息）完整结束后「待继续」——暂停在下一段
  /// 专注起点等按键（开始专注需要用户在场承诺，防人不在时专注空跑记假统计）；
  /// 专注结束永远自动进休息（休息是被动的，不需要承诺）。
  /// true：全部阶段自动续上（旧行为）。
  final bool autoContinue;

  PomodoroConfig copyWith({
    Duration? focusDuration,
    Duration? shortBreakDuration,
    Duration? longBreakDuration,
    int? roundsBeforeLongBreak,
    bool? autoContinue,
  }) {
    return PomodoroConfig(
      focusDuration: focusDuration ?? this.focusDuration,
      shortBreakDuration: shortBreakDuration ?? this.shortBreakDuration,
      longBreakDuration: longBreakDuration ?? this.longBreakDuration,
      roundsBeforeLongBreak:
          roundsBeforeLongBreak ?? this.roundsBeforeLongBreak,
      autoContinue: autoContinue ?? this.autoContinue,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'focusMillis': focusDuration.inMilliseconds,
        'shortBreakMillis': shortBreakDuration.inMilliseconds,
        'longBreakMillis': longBreakDuration.inMilliseconds,
        'roundsBeforeLongBreak': roundsBeforeLongBreak,
        'autoContinue': autoContinue,
      };

  factory PomodoroConfig.fromJson(Map<String, dynamic> json) {
    return PomodoroConfig(
      focusDuration: Duration(milliseconds: json['focusMillis'] as int),
      shortBreakDuration:
          Duration(milliseconds: json['shortBreakMillis'] as int),
      longBreakDuration: Duration(milliseconds: json['longBreakMillis'] as int),
      roundsBeforeLongBreak: json['roundsBeforeLongBreak'] as int,
      autoContinue: json['autoContinue'] as bool? ?? false,
    );
  }
}

/// 计时引擎。所有公共方法都是同步的，便于在 Riverpod notifier 中直接驱动。
class TimerEngine {
  TimerEngine({
    PomodoroConfig config = const PomodoroConfig(),
    DateTime Function()? clock,
  })  : _config = config,
        _clock = clock ?? DateTime.now;

  PomodoroConfig _config;

  /// 时间源，测试时注入假时钟；默认墙上时钟
  final DateTime Function() _clock;

  TimerPhase _phase = TimerPhase.idle;

  /// 暂停前所处的阶段（focusing / shortBreak / longBreak）
  TimerPhase? _phaseBeforePause;

  /// 运行中阶段的「结束墙上时间戳」（毫秒）。暂停 / 空闲时为 null。
  int? _endsAtMillis;

  /// 暂停时冻结的剩余毫秒数，恢复时据此重算结束时间戳。
  int? _pausedRemainingMillis;

  /// 当前专注段的「开始墙上时间戳」（毫秒）。专注统计的真值源（R9）：
  /// 已做时长 = 现在 - 开始 - 段内暂停总长，与「计划时长 - 剩余」无关——
  /// 后者会被 addTime 加时污染（remaining 变大 → 已做变小甚至为负，
  /// 加的时间自然完成时被吞掉，用户实测「+5 分钟不进统计」即此）。
  /// null 表示当前无进行中的专注段（待继续的新段尚未开始）。
  int? _phaseStartedAtMillis;

  /// 已完成的专注轮数（用于判断该进长休还是短休；跳过专注不计入）。
  int _completedFocusRounds = 0;

  /// 已结束（含被跳过）专注段的真实累计毫秒，不含进行中当前轮（US-D01 诚实统计）。
  int _accumulatedFocusMillis = 0;

  /// 已结束专注段的墙上时间区间列表（开始毫秒, 结束毫秒），按完成顺序（R8）。
  /// 详细时间轴按段渲染：块与块之间的空隙即休息/离开——会话级 startAt→endAt
  /// 整段画块会把休息时间也涂满（用户实测「时间轴完全连续」即此缺陷）。
  final List<(int, int)> _focusSegments = [];

  /// 专注阶段内的暂停（中断）区间（开始毫秒, 结束毫秒；进行中的暂停 end=null）。
  /// 只在「专注中暂停」记录——休息阶段的暂停不算分心（US-D02）。
  /// 注意：段区间（_focusSegments）是含暂停的墙钟区间（R9 起按实际段长），
  /// 暂停被包在段内不可见，中断统计必须独立记录。
  final List<(int, int?)> _pauses = [];

  // ---------------------------------------------------------------- 只读状态

  /// 当前阶段
  TimerPhase get phase => _phase;

  /// 暂停前的阶段（仅 paused 态有意义）
  TimerPhase? get phaseBeforePause => _phaseBeforePause;

  /// 已完成的专注轮数（自然结束才计入；跳过专注不算完成）
  int get completedFocusRounds => _completedFocusRounds;

  /// 已结束专注段的真实累计毫秒（自然完成计整轮，跳过只计已做部分）；
  /// 进行中的当前轮不在其内（由 SessionRecordBuilder 按剩余时间折算叠加）。
  int get accumulatedFocusMillis => _accumulatedFocusMillis;

  /// 已结束专注段的墙上时间区间（R8），只读副本
  List<(int, int)> get focusSegments => List.unmodifiable(_focusSegments);

  /// 专注阶段内的暂停（中断）区间（US-D02），只读副本；末条 end=null 表示暂停中
  List<(int, int?)> get pauses => List.unmodifiable(_pauses);

  /// 当前专注段的开始墙上时间戳（毫秒）；无进行中专注段时为 null
  int? get phaseStartedAtMillis => _phaseStartedAtMillis;

  /// 进行中专注段的真实已做毫秒数（R9 诚实统计的真值源）：
  /// 已做 = 有效现在 - 段开始 - 段内暂停总长。暂停中冻结（有效现在 =
  /// 未闭合暂停的起点）；「待继续」新段未开始 = 0。
  /// 旧版持久化数据无开始时间戳时回退「计划时长 - 剩余」折算（与旧行为一致）。
  int get currentFocusDoneMillis {
    final inFocus = _phase == TimerPhase.focusing ||
        (_phase == TimerPhase.paused &&
            _phaseBeforePause == TimerPhase.focusing);
    if (!inFocus) return 0;
    final start = _phaseStartedAtMillis;
    if (start == null) {
      // 旧数据回退；「待继续」冻结整轮 → 折算为 0，语义一致
      final legacy =
          _config.focusDuration.inMilliseconds - remaining.inMilliseconds;
      return legacy > 0 ? legacy : 0;
    }
    // 防御（恢复边界）：focusing 却无结束时间戳属异常持久化，此时若仍按
    // 墙钟累积会随时间无限增长（用户实测「一天统计超过 24 小时」的幽灵来源），
    // 按「未计时」处理，宁可少记不可多记。
    if (_phase == TimerPhase.focusing && _endsAtMillis == null) return 0;
    var effectiveNow = _clock().millisecondsSinceEpoch;
    if (_phase == TimerPhase.paused) {
      final openIdx = _pauses.lastIndexWhere((p) => p.$2 == null);
      if (openIdx < 0) return 0; // 暂停于专注但无中断记录 = 待继续（防御）
      effectiveNow = _pauses[openIdx].$1; // 冻结语义：停在暂停发生时刻
    }
    final done =
        effectiveNow - start - _pausedMillisWithin(start, effectiveNow);
    return done > 0 ? done : 0;
  }

  /// [_pauses] 与墙钟区间 [start, end) 的交集总长（毫秒）。
  /// 未闭合的进行中暂停按 end 截断（end 即有效现在）。
  int _pausedMillisWithin(int start, int end) {
    var total = 0;
    for (final p in _pauses) {
      final lo = p.$1 > start ? p.$1 : start;
      final pe = p.$2 ?? end;
      final hi = pe < end ? pe : end;
      if (hi > lo) total += hi - lo;
    }
    return total;
  }

  /// 关闭最后一条未关闭的暂停记录（resume/skip/finish 共用）。
  /// 无未关闭记录时静默跳过（「待继续」态 resume 无对应暂停可关）。
  void _closeOpenPause() {
    final i = _pauses.lastIndexWhere((p) => p.$2 == null);
    if (i >= 0) {
      _pauses[i] = (_pauses[i].$1, _clock().millisecondsSinceEpoch);
    }
  }

  /// 当前配置
  PomodoroConfig get config => _config;

  /// 是否处于运行态（专注 / 短休 / 长休，且未暂停）
  bool get isRunning =>
      _endsAtMillis != null &&
      (_phase == TimerPhase.focusing ||
          _phase == TimerPhase.shortBreak ||
          _phase == TimerPhase.longBreak);

  /// 当前阶段剩余时间。
  ///
  /// 核心算法：运行中 = 结束时间戳 - 当前时间戳（下限 0）；
  /// 暂停 = 冻结值；空闲 = 一整轮专注时长；已结束 = 0。
  Duration get remaining {
    if (isRunning) {
      final left = _endsAtMillis! - _clock().millisecondsSinceEpoch;
      return Duration(milliseconds: left > 0 ? left : 0);
    }
    if (_phase == TimerPhase.paused) {
      return Duration(milliseconds: _pausedRemainingMillis ?? 0);
    }
    if (_phase == TimerPhase.idle) return _config.focusDuration;
    return Duration.zero;
  }

  /// 当前阶段的计划总时长（UI 画进度环用）
  Duration get currentPhaseTotal {
    if (_phase == TimerPhase.paused && _phaseBeforePause != null) {
      return _durationOf(_phaseBeforePause!);
    }
    return _durationOf(_phase);
  }

  // ---------------------------------------------------------------- 驱动

  /// 由上层周期调用（建议每 500ms）。
  /// 若运行中的阶段已越过结束时间戳，则轮转到下一阶段。
  /// 返回是否有状态变化，便于上层决定是否重绘 / 持久化。
  bool tick() {
    if (!isRunning) return false;
    if (_clock().millisecondsSinceEpoch < _endsAtMillis!) return false;
    _advanceToNextPhase(natural: true);
    return true;
  }

  /// 开始一轮新的专注。允许从 idle / completed 调用。
  void start() {
    assert(_phase == TimerPhase.idle || _phase == TimerPhase.completed,
        'start() 仅允许在 idle/completed 态调用');
    if (_phase == TimerPhase.completed) {
      _completedFocusRounds = 0; // 重新开始，轮数与真实累计清零
      _accumulatedFocusMillis = 0;
      _focusSegments.clear();
      _pauses.clear();
    }
    _beginPhase(TimerPhase.focusing);
  }

  /// 暂停（仅运行态有效）。冻结剩余时间，记住原阶段。
  /// 专注阶段的暂停记为一次中断（US-D02），休息阶段暂停不记。
  void pause() {
    if (!isRunning) return;
    final now = _clock().millisecondsSinceEpoch;
    if (_phase == TimerPhase.focusing) _pauses.add((now, null));
    _pausedRemainingMillis = _endsAtMillis! - now;
    if (_pausedRemainingMillis! < 0) _pausedRemainingMillis = 0;
    _phaseBeforePause = _phase;
    _endsAtMillis = null;
    _phase = TimerPhase.paused;
  }

  /// 从暂停恢复：用冻结的剩余时间重算结束时间戳。
  /// 「待继续」的 resume = 新专注段真正开始，在此烙开始时间戳（R9）。
  void resume() {
    if (_phase != TimerPhase.paused || _phaseBeforePause == null) return;
    if (_phaseBeforePause == TimerPhase.focusing) _closeOpenPause();
    _phase = _phaseBeforePause!;
    _phaseBeforePause = null;
    _endsAtMillis =
        _clock().millisecondsSinceEpoch + (_pausedRemainingMillis ?? 0);
    _pausedRemainingMillis = null;
    if (_phase == TimerPhase.focusing && _phaseStartedAtMillis == null) {
      _phaseStartedAtMillis = _clock().millisecondsSinceEpoch;
    }
  }

  /// 恢复时把「运行中」的阶段冻结到 [aliveAtMillis]（进程最后一次存活时刻）。
  ///
  /// 用户口径：**主动关闭 / 关机期间不计入统计**——程序与用户共同保障的
  /// 是「进程存活期间的连续计时」。正常路径退出前会先暂停，因此恢复时仍为
  /// 运行态只可能是被强制关闭/崩溃；此时把关机期间从统计与剩余中整段剔除，
  /// 语义等价于在 [aliveAtMillis] 发生了一次暂停（resume 即从此处继续）。
  ///
  /// [aliveAtMillis] 为 null（旧版数据无心跳）时保守取阶段起点：当前段计 0，
  /// 宁可少记不可多记。返回是否发生了冻结（仅运行态有效）。
  bool freezeForRestore(int? aliveAtMillis) {
    if (!isRunning) return false;
    final now = _clock().millisecondsSinceEpoch;
    var at = aliveAtMillis ?? _phaseStartedAtMillis ?? now;
    if (at > now) at = now;
    if (_phase == TimerPhase.focusing) _pauses.add((at, null));
    final remaining = _endsAtMillis! - at;
    _pausedRemainingMillis = remaining > 0 ? remaining : 0;
    _phaseBeforePause = _phase;
    _endsAtMillis = null;
    _phase = TimerPhase.paused;
    return true;
  }

  /// 跳过当前阶段（立即轮转到下一阶段）。
  /// 暂停态下跳过等价于对暂停前阶段执行跳过（按冻结剩余折算已做部分）。
  /// 诚实统计（US-D01，真机反馈 R1）：跳过专注**不计完成轮数**，
  /// 只把真实已做的部分计入 [accumulatedFocusMillis]。
  void skipPhase() {
    final int remainingMillis;
    if (_phase == TimerPhase.paused && _phaseBeforePause != null) {
      // 先恢复到原阶段再走正常轮转；已做部分按冻结剩余折算
      if (_phaseBeforePause == TimerPhase.focusing) _closeOpenPause();
      remainingMillis = _pausedRemainingMillis ?? 0;
      _phase = _phaseBeforePause!;
      _phaseBeforePause = null;
      _pausedRemainingMillis = null;
      _endsAtMillis = _clock().millisecondsSinceEpoch;
    } else if (isRunning) {
      remainingMillis =
          (_endsAtMillis! - _clock().millisecondsSinceEpoch).clamp(0, 1 << 62);
    } else {
      return;
    }
    _advanceToNextPhase(natural: false, remainingMillis: remainingMillis);
  }

  /// 主动结束本次番茄会话 → completed。
  void finish() {
    if (_phase == TimerPhase.idle || _phase == TimerPhase.completed) return;
    // 暂停中结束：关闭未闭合的中断记录（该次暂停即最终中断）
    if (_phase == TimerPhase.paused &&
        _phaseBeforePause == TimerPhase.focusing) {
      _closeOpenPause();
    }
    _phase = TimerPhase.completed;
    _phaseBeforePause = null;
    _endsAtMillis = null;
    _pausedRemainingMillis = null;
    _phaseStartedAtMillis = null;
  }

  /// 完全复位 → idle，轮数与真实累计清零。
  void reset() {
    _phase = TimerPhase.idle;
    _phaseBeforePause = null;
    _endsAtMillis = null;
    _pausedRemainingMillis = null;
    _phaseStartedAtMillis = null;
    _completedFocusRounds = 0;
    _accumulatedFocusMillis = 0;
    _focusSegments.clear();
    _pauses.clear();
  }

  /// 给当前阶段加时间（默认命令映射里的「上一首 = +5 分钟」用）。
  void addTime(Duration delta) {
    if (isRunning) {
      _endsAtMillis = _endsAtMillis! + delta.inMilliseconds;
    } else if (_phase == TimerPhase.paused) {
      _pausedRemainingMillis =
          (_pausedRemainingMillis ?? 0) + delta.inMilliseconds;
    }
  }

  /// 运行中更新配置。新时长只影响之后开始的阶段，不打断当前阶段。
  set config(PomodoroConfig value) => _config = value;

  // ---------------------------------------------------------------- 内部

  /// 阶段轮转（真机反馈 R4 语义）：
  /// - 专注结束（一轮的前半段）→ **永远自动进休息**：休息是被动的，
  ///   不需要用户承诺，立即开始；
  /// - 休息结束（一轮完整结束）→ autoContinue=true 自动开始下一段专注；
  ///   false（默认）则「待继续」：暂停在专注起点等按键——开始专注需要
  ///   用户在场承诺，否则人不在时专注空跑会记出假统计。
  ///
  /// [natural] 为 true 表示时间自然走完（tick 驱动）：计完成轮数；
  /// false 表示用户跳过：不计轮数。
  /// 两种路径的已做时长都按「段开始时间戳 → 段结束，扣除段内暂停」的
  /// 实际墙钟区间入账（R9 以计时为主）：addTime 加时长自然完成时
  /// 加时部分如实计入；旧版持久化数据无开始时间戳时回退按计划折算。
  void _advanceToNextPhase({required bool natural, int? remainingMillis}) {
    final finished = _phase;
    if (finished == TimerPhase.focusing) {
      final focusMillis = _config.focusDuration.inMilliseconds;
      if (natural) {
        final end = _endsAtMillis ?? _clock().millisecondsSinceEpoch;
        final start = _phaseStartedAtMillis ?? (end - focusMillis);
        final actual = end - start - _pausedMillisWithin(start, end);
        _focusSegments.add((start, end));
        _completedFocusRounds++;
        _accumulatedFocusMillis += actual > 0 ? actual : 0;
      } else {
        final now = _clock().millisecondsSinceEpoch;
        final start = _phaseStartedAtMillis;
        final int done;
        if (start != null) {
          done = now - start - _pausedMillisWithin(start, now);
        } else {
          // 旧数据回退：按计划时长 - 冻结/剩余折算
          done = focusMillis - (remainingMillis ?? 0);
        }
        if (done > 0) {
          _focusSegments.add((start ?? (now - done), now));
          _accumulatedFocusMillis += done;
        }
      }
      // 守卫：0 轮时 0 % N == 0 会误判长休（跳过后轮数未涨的场景）
      final needLong = _completedFocusRounds > 0 &&
          _completedFocusRounds % _config.roundsBeforeLongBreak == 0;
      _beginPhase(needLong ? TimerPhase.longBreak : TimerPhase.shortBreak);
    } else if (finished == TimerPhase.shortBreak ||
        finished == TimerPhase.longBreak) {
      _enterNextFocus();
    }
  }

  /// 休息结束进入下一段专注：autoContinue=true 直接开始计时；
  /// false（默认）则「待继续」——暂停在专注起点（复用暂停态语义：
  /// [_phaseBeforePause]=focusing，剩余时间冻结为整轮，resume 即开始）。
  void _enterNextFocus() {
    if (_config.autoContinue) {
      _beginPhase(TimerPhase.focusing);
      return;
    }
    _phase = TimerPhase.paused;
    _phaseBeforePause = TimerPhase.focusing;
    _endsAtMillis = null;
    _pausedRemainingMillis = _config.focusDuration.inMilliseconds;
    _phaseStartedAtMillis = null; // 新段未开始，resume 时才烙印（R9）
  }

  void _beginPhase(TimerPhase phase) {
    _phase = phase;
    _endsAtMillis =
        _clock().millisecondsSinceEpoch + _durationOf(phase).inMilliseconds;
    _pausedRemainingMillis = null;
    _phaseStartedAtMillis = _clock().millisecondsSinceEpoch;
  }

  Duration _durationOf(TimerPhase phase) => switch (phase) {
        TimerPhase.focusing => _config.focusDuration,
        TimerPhase.shortBreak => _config.shortBreakDuration,
        TimerPhase.longBreak => _config.longBreakDuration,
        _ => Duration.zero,
      };

  // ---------------------------------------------------------------- 持久化

  /// 序列化为可持久化 JSON。记录的是墙上时间戳，杀后台恢复后时间差自动成立。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'config': _config.toJson(),
        'phase': _phase.name,
        'phaseBeforePause': _phaseBeforePause?.name,
        'endsAtMillis': _endsAtMillis,
        'pausedRemainingMillis': _pausedRemainingMillis,
        'phaseStartedAtMillis': _phaseStartedAtMillis,
        'completedFocusRounds': _completedFocusRounds,
        'accumulatedFocusMillis': _accumulatedFocusMillis,
        'focusSegments': <List<int>>[
          for (final seg in _focusSegments) <int>[seg.$1, seg.$2],
        ],
        // 中断记录（US-D02）：[start, end]，进行中的暂停 end 为 null
        'pauses': <List<int?>>[
          for (final p in _pauses) <int?>[p.$1, p.$2],
        ],
      };

  /// 从 JSON 恢复。恢复后第一次 [tick] 会自动补齐进程死亡期间流逝的时间。
  factory TimerEngine.fromJson(
    Map<String, dynamic> json, {
    DateTime Function()? clock,
  }) {
    final engine = TimerEngine(
      config: PomodoroConfig.fromJson(
          (json['config'] as Map).cast<String, dynamic>()),
      clock: clock,
    );
    engine._phase = TimerPhase.values.byName(json['phase'] as String);
    final before = json['phaseBeforePause'] as String?;
    engine._phaseBeforePause =
        before == null ? null : TimerPhase.values.byName(before);
    engine._endsAtMillis = json['endsAtMillis'] as int?;
    engine._pausedRemainingMillis = json['pausedRemainingMillis'] as int?;
    engine._phaseStartedAtMillis = json['phaseStartedAtMillis'] as int?;
    engine._completedFocusRounds = json['completedFocusRounds'] as int? ?? 0;
    engine._accumulatedFocusMillis =
        json['accumulatedFocusMillis'] as int? ?? 0;
    final segments = json['focusSegments'] as List?;
    if (segments != null) {
      for (final seg in segments) {
        if (seg is List && seg.length == 2) {
          engine._focusSegments.add((seg[0] as int, seg[1] as int));
        }
      }
    }
    final pauses = json['pauses'] as List?;
    if (pauses != null) {
      for (final p in pauses) {
        if (p is List && p.length == 2 && p[0] is int) {
          engine._pauses.add((p[0] as int, p[1] as int?));
        }
      }
    }
    return engine;
  }
}
