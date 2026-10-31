/// 正计时（秒表）引擎：MVP 的第二种计时模式（ADR-0005 确定的唯二模式之一）。
///
/// 与 [TimerEngine]（番茄倒计时）平级、互不依赖：
/// 「一种计时模式 = 一个独立引擎类」是本项目预留的模式扩展点——
/// 未来新增模式（如 50/10 深度工作、Flowtime）时新建同类引擎，
/// 由 FocusController 按用户选择的模式装配，互不修改。
///
/// 语义：
/// - 不预设时长，从 0 开始累计已专注时间，用于客观记录与复盘；
/// - 支持暂停 / 恢复 / 结束；
/// - 支持「打点」（[addMark]）：正计时模式下按「上一首」记录一个时间标记，
///   用于标记一段工作中的关键节点；
/// - 计时一律用时间戳差值，绝不每秒累加（同 TimerEngine 的设计原则）。
library;

/// 正计时引擎状态。
enum CountUpPhase {
  /// 空闲，未开始
  idle,

  /// 计时中
  running,

  /// 已暂停
  paused,

  /// 已结束（用户主动结束，可读取最终时长与打点）
  finished,
}

/// 状态中文展示名（页面与通知共用，避免文案漂移）。
extension CountUpPhaseX on CountUpPhase {
  /// 展示名
  String get label => switch (this) {
        CountUpPhase.idle => '准备开始',
        CountUpPhase.running => '专注中',
        CountUpPhase.paused => '已暂停',
        CountUpPhase.finished => '已完成',
      };
}

class CountUpTimer {
  CountUpTimer({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// 时间源，测试时注入假时钟；默认墙上时钟
  final DateTime Function() _clock;

  CountUpPhase _phase = CountUpPhase.idle;

  /// 运行中的「起始墙上时间戳」（毫秒）。该值已扣除暂停累计，
  /// 使得 `now - _startedAtMillis` 始终等于有效已计时长。
  int? _startedAtMillis;

  /// 暂停时冻结的已计毫秒数，恢复时据此回推 [_startedAtMillis]。
  int? _pausedElapsedMillis;

  /// 打点列表：每个元素是「相对开始计时的偏移毫秒数」，按时间升序。
  final List<int> _markOffsetsMillis = <int>[];

  /// 暂停（中断）区间（开始毫秒, 结束毫秒；进行中的暂停 end=null）（US-D02）。
  /// 正计时无休息阶段，所有暂停都是中断。
  final List<(int, int?)> _pauses = [];

  // ---------------------------------------------------------------- 只读状态

  CountUpPhase get phase => _phase;

  bool get isRunning =>
      _phase == CountUpPhase.running && _startedAtMillis != null;

  /// 已计时时间：运行中 = now - 起始时间戳；暂停 = 冻结值；其余 = 0。
  Duration get elapsed {
    if (isRunning) {
      final e = _clock().millisecondsSinceEpoch - _startedAtMillis!;
      return Duration(milliseconds: e > 0 ? e : 0);
    }
    if (_phase == CountUpPhase.paused) {
      return Duration(milliseconds: _pausedElapsedMillis ?? 0);
    }
    if (_phase == CountUpPhase.finished) {
      return Duration(milliseconds: _pausedElapsedMillis ?? 0);
    }
    return Duration.zero;
  }

  /// 打点列表（只读副本）
  List<Duration> get marks =>
      _markOffsetsMillis.map((m) => Duration(milliseconds: m)).toList();

  /// 暂停（中断）区间（US-D02），只读副本；末条 end=null 表示暂停中
  List<(int, int?)> get pauses => List.unmodifiable(_pauses);

  // ---------------------------------------------------------------- 操作

  /// 开始正计时。允许从 idle / finished 调用（finished 时清零重新开始）。
  void start() {
    assert(_phase == CountUpPhase.idle || _phase == CountUpPhase.finished,
        'start() 仅允许在 idle/finished 态调用');
    _markOffsetsMillis.clear();
    _pauses.clear();
    _pausedElapsedMillis = null;
    _startedAtMillis = _clock().millisecondsSinceEpoch;
    _phase = CountUpPhase.running;
  }

  /// 暂停：冻结已计时长，并记为一次中断开始（US-D02）。
  void pause() {
    if (!isRunning) return;
    final now = _clock().millisecondsSinceEpoch;
    _pauses.add((now, null));
    _pausedElapsedMillis = now - _startedAtMillis!;
    if (_pausedElapsedMillis! < 0) _pausedElapsedMillis = 0;
    _startedAtMillis = null;
    _phase = CountUpPhase.paused;
  }

  /// 恢复：回推起始时间戳，使已计时长连续；闭合本次中断。
  void resume() {
    if (_phase != CountUpPhase.paused) return;
    final i = _pauses.lastIndexWhere((p) => p.$2 == null);
    if (i >= 0) {
      _pauses[i] = (_pauses[i].$1, _clock().millisecondsSinceEpoch);
    }
    _startedAtMillis = _clock().millisecondsSinceEpoch -
        (_pausedElapsedMillis ?? 0);
    _pausedElapsedMillis = null;
    _phase = CountUpPhase.running;
  }

  /// 恢复时把「运行中」的正计时冻结到 [aliveAtMillis]（进程最后一次存活
  /// 时刻）。用户口径：**主动关闭 / 关机期间不计入统计**——恢复时仍为运行态
  /// 只可能是被强制关闭/崩溃，此时关机期间整段剔除（等价于在存活点暂停）。
  /// [aliveAtMillis] 为 null（旧版数据）时保守取起点：elapsed 计 0。
  /// 返回是否发生了冻结（仅运行态有效）。
  bool freezeForRestore(int? aliveAtMillis) {
    if (!isRunning) return false;
    final now = _clock().millisecondsSinceEpoch;
    var at = aliveAtMillis ?? _startedAtMillis ?? now;
    if (at > now) at = now;
    _pauses.add((at, null));
    final e = at - _startedAtMillis!;
    _pausedElapsedMillis = e > 0 ? e : 0;
    _startedAtMillis = null;
    _phase = CountUpPhase.paused;
    return true;
  }

  /// 打点：记录当前已计时长为一个标记点。仅运行态有效。
  /// 返回新增打点的索引；非运行态返回 -1。
  int addMark() {
    if (!isRunning) return -1;
    _markOffsetsMillis.add(elapsed.inMilliseconds);
    return _markOffsetsMillis.length - 1;
  }

  /// 结束：冻结最终时长与打点，进入 finished。
  /// 暂停中结束：闭合本次中断（暂停跨度即最终中断）。
  void finish() {
    if (_phase == CountUpPhase.idle || _phase == CountUpPhase.finished) return;
    final now = _clock().millisecondsSinceEpoch;
    final i = _pauses.lastIndexWhere((p) => p.$2 == null);
    if (i >= 0) _pauses[i] = (_pauses[i].$1, now);
    if (isRunning) {
      _pausedElapsedMillis = now - _startedAtMillis!;
    }
    _startedAtMillis = null;
    _phase = CountUpPhase.finished;
  }

  /// 完全复位 → idle。
  void reset() {
    _phase = CountUpPhase.idle;
    _startedAtMillis = null;
    _pausedElapsedMillis = null;
    _markOffsetsMillis.clear();
    _pauses.clear();
  }

  // ---------------------------------------------------------------- 持久化

  Map<String, dynamic> toJson() => <String, dynamic>{
        'phase': _phase.name,
        'startedAtMillis': _startedAtMillis,
        'pausedElapsedMillis': _pausedElapsedMillis,
        'markOffsetsMillis': _markOffsetsMillis,
        // 中断记录（US-D02）：[start, end]，进行中的暂停 end 为 null
        'pauses': <List<int?>>[
          for (final p in _pauses) <int?>[p.$1, p.$2],
        ],
      };

  /// 从 JSON 恢复。运行态恢复后，进程死亡期间流逝的时间自动计入
  /// （正计时语义：人在工作，计时就不该丢）。
  factory CountUpTimer.fromJson(
    Map<String, dynamic> json, {
    DateTime Function()? clock,
  }) {
    final timer = CountUpTimer(clock: clock);
    timer._phase = CountUpPhase.values.byName(json['phase'] as String);
    timer._startedAtMillis = json['startedAtMillis'] as int?;
    timer._pausedElapsedMillis = json['pausedElapsedMillis'] as int?;
    final marks = json['markOffsetsMillis'] as List?;
    if (marks != null) {
      timer._markOffsetsMillis.addAll(marks.cast<int>());
    }
    final pauses = json['pauses'] as List?;
    if (pauses != null) {
      for (final p in pauses) {
        if (p is List && p.length == 2 && p[0] is int) {
          timer._pauses.add((p[0] as int, p[1] as int?));
        }
      }
    }
    return timer;
  }
}
