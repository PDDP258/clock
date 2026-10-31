/// 专注控制器：连接计时引擎（番茄/正计时）、CommandBus 与 FocusAudioHandler。
///
/// 职责：
/// 1. 订阅 CommandBus 命令流，先经 [resolveForMode] 按当前模式改写语义
///    （上一曲：番茄=+5 分钟 / 正计时=打点，ADR-0005），再驱动对应引擎；
/// 2. 每 500ms 触发一次引擎 tick() 驱动阶段轮转并刷新 UI 状态；
/// 3. 按键接管策略：开始专注且「计时期间接管实体按键」开关开启时
///    acquireKeys() 霸占 MediaSession；结束/退出时 releaseKeys() 还给
///    M500 系统音乐 App；
/// 4. 每次状态变化把引擎 toJson() 写入 SharedPreferences（两种模式各自
///    独立持久化），启动时恢复，实现杀后台可续；
/// 5. 按键声音反馈：命令被接收即发声确认（<100ms），阶段轮转发提醒。
///
/// 两种模式各持一个引擎实例、互不 import（一模式一引擎，架构 §9.5）。
/// 模式切换仅在两模式均无进行中会话时开放（UI 层置灰保证）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MethodChannel, MissingPluginException;
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/commands/app_command.dart';
import '../../../core/commands/mode_dispatch.dart';
import '../../../core/feedback/key_feedback.dart';
import '../../settings/application/tone_settings.dart';
import '../../../core/media/key_event_log.dart';
import '../../../core/media/media_key_event.dart';
import '../../../core/timer/count_up_timer.dart';
import '../../../core/timer/pause_release_policy.dart';
import '../../../core/timer/session_record.dart';
import '../../../core/timer/time_format.dart';
import '../../../core/timer/timer_engine.dart';
import '../../../core/timer/timer_mode.dart';
import '../../../platform/db/app_database.dart';
import '../../../platform/feedback/key_feedback_service.dart';
import '../../../platform/media_session/focus_audio_handler.dart';
import '../../../platform/prefs/prefs_provider.dart';
import '../../stats/application/stats_controller.dart';

// ---------------------------------------------------------------- Providers

/// 命令总线（main.dart 中 override 注入，与 AudioService 共享同一实例）
final commandBusProvider = Provider<CommandBus>(
  (ref) => throw UnimplementedError('需在 main.dart 的 ProviderScope 中 override'),
);

/// 按键映射配置（US-A08）：CommandBus 运行时映射的可观察镜像。
///
/// CommandBus 是纯 Dart 可变对象（handler 侧直接读 keyMap），无法被
/// ref.watch 感知；本 Notifier 作为设置页编辑的唯一入口，改动同时
/// 写回 CommandBus（立即生效，含 bindsMultiTap 对 300ms 窗口的影响）
/// 与 SharedPreferences（重启恢复，main.dart 装配时读回）。
final keyMapConfigProvider =
    StateNotifierProvider<KeyMapConfigNotifier, KeyMapConfig>((ref) =>
        KeyMapConfigNotifier(
          ref.watch(commandBusProvider),
          ref.watch(sharedPreferencesProvider),
        ));

/// 映射的编辑、热生效与持久化。
class KeyMapConfigNotifier extends StateNotifier<KeyMapConfig> {
  KeyMapConfigNotifier(this._bus, this._prefs) : super(_bus.keyMap);

  final CommandBus _bus;
  final SharedPreferences _prefs;

  /// 重映射单个按键。[AppCommand.ignored] 视为「移除该键映射」。
  Future<void> remap(MediaKeyEvent event, AppCommand command) async {
    final mapping = Map<MediaKeyEvent, AppCommand>.of(state.mapping);
    if (command == AppCommand.ignored) {
      mapping.remove(event);
    } else {
      mapping[event] = command;
    }
    await _apply(KeyMapConfig(mapping: mapping));
  }

  /// 恢复出厂默认映射（同时清除持久化的自定义值，语义=从未自定义）。
  Future<void> resetToDefaults() async {
    final defaults = KeyMapConfig.defaults();
    state = defaults;
    _bus.keyMap = defaults;
    await _prefs.remove(kKeyMapStorageKey);
  }

  Future<void> _apply(KeyMapConfig config) async {
    state = config;
    _bus.keyMap = config;
    await _prefs.setString(kKeyMapStorageKey, jsonEncode(config.toJson()));
  }
}

/// 按键自检日志（main.dart 中创建并挂接 CommandBus.onDispatch 后 override 注入）
final keyEventLogProvider = Provider<KeyEventLog>(
  (ref) => throw UnimplementedError('需在 main.dart 的 ProviderScope 中 override'),
);

/// 媒体按键处理器（main.dart 中 AudioService.init 后 override 注入）
final focusAudioHandlerProvider = Provider<FocusAudioHandler>(
  (ref) => throw UnimplementedError('需在 main.dart 的 ProviderScope 中 override'),
);

/// 「计时期间接管实体按键」开关。关闭后计时与按键完全解耦，
/// 实体按键始终归 M500 系统音乐 App。
final keysTakeoverProvider =
    StateNotifierProvider<KeysTakeoverNotifier, bool>(
        (ref) => KeysTakeoverNotifier(ref.watch(sharedPreferencesProvider)));

/// 开关状态 + 持久化。
class KeysTakeoverNotifier extends StateNotifier<bool> {
  KeysTakeoverNotifier(this._prefs)
      : super(_prefs.getBool(_kKeysTakeover) ?? true);

  static const _kKeysTakeover = 'keys_takeover_enabled';
  final SharedPreferences _prefs;

  Future<void> setEnabled(bool value) async {
    state = value;
    await _prefs.setBool(_kKeysTakeover, value);
  }
}

/// 当前计时模式（番茄倒计时 / 正计时），持久化。
final timerModeProvider = StateNotifierProvider<TimerModeNotifier, TimerMode>(
    (ref) => TimerModeNotifier(ref.watch(sharedPreferencesProvider)));

/// 模式的读写与持久化。
class TimerModeNotifier extends StateNotifier<TimerMode> {
  TimerModeNotifier(this._prefs)
      : super(TimerModeX.fromStorageKey(_prefs.getString(_kTimerMode)));

  static const _kTimerMode = 'timer_mode';
  final SharedPreferences _prefs;

  Future<void> setMode(TimerMode mode) async {
    state = mode;
    await _prefs.setString(_kTimerMode, mode.storageKey);
  }
}

/// 当前任务/标签（US-B05）：会话开始时由 FocusController 烙印到 drift 行；
/// null = 无标签。自定义标签清单同存 SP（选择器复用）。
final currentTagProvider = StateNotifierProvider<CurrentTagNotifier, String?>(
    (ref) => CurrentTagNotifier(ref.watch(sharedPreferencesProvider)));

/// 标签的读写、清单管理与持久化。
class CurrentTagNotifier extends StateNotifier<String?> {
  CurrentTagNotifier(this._prefs) : super(_prefs.getString(_kCurrentTag));

  static const _kCurrentTag = 'current_tag';
  static const _kTagList = 'tag_list';
  static const _kMaxTags = 12;
  final SharedPreferences _prefs;

  /// 用户保存过的标签清单（新标签在前）。
  List<String> get savedTags {
    final raw = _prefs.getString(_kTagList);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } on FormatException {
      return const [];
    }
  }

  /// 选定当前标签；非空标签顺手存入清单（去重、前移、截断）。
  Future<void> setTag(String? tag) async {
    state = tag;
    if (tag == null) {
      await _prefs.remove(_kCurrentTag);
    } else {
      await _prefs.setString(_kCurrentTag, tag);
      await addSavedTag(tag);
    }
  }

  /// 把标签加入清单（已存在则移到最前）。
  Future<void> addSavedTag(String tag) async {
    final list = [tag, ...savedTags.where((t) => t != tag)];
    if (list.length > _kMaxTags) list.removeRange(_kMaxTags, list.length);
    await _prefs.setString(_kTagList, jsonEncode(list));
  }

  /// 从清单移除标签；若正被选中则一并清空当前标签。
  Future<void> removeSavedTag(String tag) async {
    final list = savedTags.where((t) => t != tag).toList();
    await _prefs.setString(_kTagList, jsonEncode(list));
    if (state == tag) await setTag(null);
  }
}

/// 暂停超时归还按键的阈值（US-C02，默认 10 分钟，可配置）。
final pauseReleaseThresholdProvider =
    StateNotifierProvider<PauseReleaseThresholdNotifier, Duration>(
        (ref) =>
            PauseReleaseThresholdNotifier(ref.watch(sharedPreferencesProvider)));

/// 阈值的读写与持久化（存分钟数）。
class PauseReleaseThresholdNotifier extends StateNotifier<Duration> {
  PauseReleaseThresholdNotifier(this._prefs)
      : super(Duration(
            minutes: _prefs.getInt(_kThresholdMinutes) ??
                PauseReleasePolicy.defaultThreshold.inMinutes));

  static const _kThresholdMinutes = 'pause_release_threshold_minutes';
  final SharedPreferences _prefs;

  Future<void> setThreshold(Duration value) async {
    state = value;
    await _prefs.setInt(_kThresholdMinutes, value.inMinutes);
  }
}

/// 番茄钟配置（持久化到 SharedPreferences）
final pomodoroConfigProvider =
    StateNotifierProvider<PomodoroConfigNotifier, PomodoroConfig>(
        (ref) => PomodoroConfigNotifier(ref.watch(sharedPreferencesProvider)));

/// 配置的读写与持久化。
class PomodoroConfigNotifier extends StateNotifier<PomodoroConfig> {
  PomodoroConfigNotifier(this._prefs) : super(_load(_prefs));

  static const _kConfig = 'pomodoro_config';
  final SharedPreferences _prefs;

  static PomodoroConfig _load(SharedPreferences prefs) {
    final raw = prefs.getString(_kConfig);
    if (raw == null) return const PomodoroConfig();
    try {
      return PomodoroConfig.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } on FormatException {
      return const PomodoroConfig();
    }
  }

  Future<void> update(PomodoroConfig config) async {
    state = config;
    await _prefs.setString(_kConfig, jsonEncode(config.toJson()));
  }
}

// ---------------------------------------------------------------- 视图状态

/// 专注页视图状态（不可变）。两种计时模式的字段并存，
/// UI 按 [mode] 取用对应一组字段。
class FocusViewState {
  const FocusViewState({
    required this.mode,
    required this.phase,
    required this.remaining,
    required this.phaseTotal,
    required this.completedRounds,
    required this.countUpPhase,
    required this.elapsed,
    required this.markCount,
    required this.keysAcquired,
    required this.lastCommand,
    this.phaseBeforePause,
  });

  /// 当前计时模式
  final TimerMode mode;

  /// 番茄：当前阶段
  final TimerPhase phase;

  /// 番茄：暂停前的阶段（仅 [phase] 为 paused 时有意义）。
  ///
  /// 暂停只是「冻结」不是「换段」——UI 的阶段色必须沿用暂停前那一段的
  /// 颜色（PD 2026-10-07：原先暂停时硬切到强调色，视觉上像是先跳去休息
  /// 阶段又跳回来）。null 表示当前不在暂停态。
  final TimerPhase? phaseBeforePause;

  /// 阶段色归属用的阶段：暂停态取暂停前的阶段，其余取当前阶段。
  ///
  /// 这样 [_phaseColor] / [_clockColor] / kicker 文案只需问它，
  /// 暂停/继续的来回切换就不会改色。
  TimerPhase get colorPhase =>
      phase == TimerPhase.paused ? (phaseBeforePause ?? phase) : phase;

  /// 番茄：当前阶段剩余时间
  final Duration remaining;

  /// 番茄：当前阶段计划总时长（进度环用）
  final Duration phaseTotal;

  /// 番茄：已完成专注轮数
  final int completedRounds;

  /// 正计时：当前状态
  final CountUpPhase countUpPhase;

  /// 正计时：已专注时长
  final Duration elapsed;

  /// 正计时：打点数
  final int markCount;

  /// 当前是否已接管实体按键
  final bool keysAcquired;

  /// 最近一次按键命令（按键提示卡高亮反馈用）
  final AppCommand? lastCommand;

  /// 番茄：是否处于计时运行中（含休息阶段）
  bool get isRunning =>
      phase == TimerPhase.focusing ||
      phase == TimerPhase.shortBreak ||
      phase == TimerPhase.longBreak;

  /// 当前模式是否有进行中的会话（运行或暂停）——模式切换置灰依据
  bool get sessionActive => switch (mode) {
        TimerMode.pomodoro => isRunning || phase == TimerPhase.paused,
        TimerMode.countUp =>
          countUpPhase == CountUpPhase.running ||
              countUpPhase == CountUpPhase.paused,
      };

  FocusViewState copyWith({
    TimerMode? mode,
    TimerPhase? phase,
    Duration? remaining,
    Duration? phaseTotal,
    int? completedRounds,
    CountUpPhase? countUpPhase,
    Duration? elapsed,
    int? markCount,
    bool? keysAcquired,
    AppCommand? lastCommand,
    TimerPhase? phaseBeforePause,
  }) {
    return FocusViewState(
      mode: mode ?? this.mode,
      phase: phase ?? this.phase,
      phaseBeforePause: phaseBeforePause ?? this.phaseBeforePause,
      remaining: remaining ?? this.remaining,
      phaseTotal: phaseTotal ?? this.phaseTotal,
      completedRounds: completedRounds ?? this.completedRounds,
      countUpPhase: countUpPhase ?? this.countUpPhase,
      elapsed: elapsed ?? this.elapsed,
      markCount: markCount ?? this.markCount,
      keysAcquired: keysAcquired ?? this.keysAcquired,
      lastCommand: lastCommand ?? this.lastCommand,
    );
  }
}

/// 专注控制器 Provider。
final focusControllerProvider =
    StateNotifierProvider<FocusController, FocusViewState>(
        FocusController.new);

// ---------------------------------------------------------------- 控制器

/// 专注控制器。
class FocusController extends StateNotifier<FocusViewState>
    with WidgetsBindingObserver {
  FocusController(Ref ref)
      : _bus = ref.read(commandBusProvider),
        _handler = ref.read(focusAudioHandlerProvider),
        _prefs = ref.read(sharedPreferencesProvider),
        _ref = ref,
        super(const FocusViewState(
          mode: TimerMode.pomodoro,
          phase: TimerPhase.idle,
          remaining: Duration(minutes: 25),
          phaseTotal: Duration(minutes: 25),
          completedRounds: 0,
          countUpPhase: CountUpPhase.idle,
          elapsed: Duration.zero,
          markCount: 0,
          keysAcquired: false,
          lastCommand: null,
        )) {
    _engine = _restoreEngine() ??
        TimerEngine(config: ref.read(pomodoroConfigProvider));
    // 配置以设置页为准：恢复出的 JSON 可能早于最近一次设置变更（R3 联动）
    _engine.config = ref.read(pomodoroConfigProvider);
    _countUp = _restoreCountUp() ?? CountUpTimer();
    // 模式跟随持久化值（timerModeProvider 已由 TimerModeNotifier 恢复）。
    // 必须在 _discardStaleDaySession 之前赋值——守卫会调 _buildSessionRecord
    // 读 _mode，late 字段先读后写会抛 LateInitializationError（R6 热修）
    _mode = ref.read(timerModeProvider);
    _sessionStartAtMillis = _prefs.getInt(_kSessionStart);
    _activeSessionId = _prefs.getInt(_kSessionId);
    _sessionTag = _prefs.getString(_kSessionTag);
    _lastSettledFocusMillis = _prefs.getInt(_kSettledFocus) ?? 0;
    _lastAliveAtMillis = _prefs.getInt(_kLastAlive);
    // 宽限窗基准先读回（跨进程连续，R9）；被杀的运行态会在下面冻结时覆写
    _pausedAtMillis = _prefs.getInt(_kPausedAt);
    // 关机/被杀期间不计入（用户口径）：恢复出运行态 → 冻结到最后的存活时刻
    _freezeRestoredRunning();
    _discardStaleDaySession();
    // 启动自愈（R8）：找回活跃行 id + 清理悬空「进行中」行、重复行与
    // 物理不可能的 0 时长幽灵行——它们正是统计翻倍/轮次异常的数据源。
    unawaited(_recoverAndRepair());
    _commandSub = _bus.commands.listen(_onCommand);
    // 设置页改配置（含 autoContinue/时长）实时下发引擎，不打断当前阶段
    ref.listen(pomodoroConfigProvider, (_, config) => _engine.config = config);
    // UI 心跳（性能 P0）：仅在有进行中会话时运行（idle/完成态停表——
    // 旧实现从启动跑到退出永久空转）；前台 500ms、后台 5s（P2 降频）。
    // 心跳只负责驱动 tick/视图刷新，计时本身由时间戳差值保证。
    WidgetsBinding.instance.addObserver(this);
    _syncTicker();
    // 恢复后若仍处于运行态且开关允许，需要重新霸占按键
    final restoredRunning =
        _engine.isRunning || _countUp.isRunning;
    if (restoredRunning && _ref.read(keysTakeoverProvider)) {
      unawaited(_handler.acquireKeys());
    }
    // 恢复到暂停态：宽限窗以持久化的暂停时刻为准（跨进程连续，R9）；
    // 旧版数据无记录时保守地以启动时刻起算一次。
    // 注：_pausedAtMillis 已在构造早期读回（含被杀运行态的冻结时刻），
    // 此处仅在为空时兜底，不得无条件覆写（否则会丢掉冻结/持久化的暂停时刻）。
    final restoredPaused = _engine.phase == TimerPhase.paused ||
        _countUp.phase == CountUpPhase.paused;
    if (restoredPaused && _pausedAtMillis == null) {
      _pausedAtMillis = DateTime.now().millisecondsSinceEpoch;
    }
    // 有恢复出的进行中会话：通知栏按钮需保持可用（US-C02 一键重新接管）
    if (restoredRunning || restoredPaused) {
      _handler.sessionActive = true;
    }
    _emit();
  }

  static const _kEngineState = 'timer_engine_state';
  static const _kCountUpState = 'count_up_timer_state';
  static const _kSessionStart = 'focus_session_start';
  static const _kSessionId = 'focus_session_db_id';
  static const _kSettledFocus = 'focus_session_settled_millis';
  static const _kSessionTag = 'focus_session_tag';
  static const _kPausedAt = 'focus_paused_at';

  /// 进程最后一次确认存活（心跳）的墙上时间戳。恢复时若仍是运行态（=上次被
  /// 强制关闭/崩溃，正常退出会先暂停），用它在 [TimerEngine.freezeForRestore]
  /// 处把「关机期间」整段排除出统计（用户口径：主动关闭/关机不计入）。
  static const _kLastAlive = 'focus_last_alive_at';

  late final TimerEngine _engine;
  late final CountUpTimer _countUp;
  late TimerMode _mode;
  final CommandBus _bus;
  final FocusAudioHandler _handler;
  final SharedPreferences _prefs;
  final Ref _ref;

  /// 进入暂停态的墙上时间戳（暂停超时释放按键用，US-C02）；
  /// 恢复/结束/新开始时清空。随 [_persist] 持久化（R9 根因 2 修复）：
  /// 旧实现冷启动恢复到暂停态时以启动时刻重算宽限窗——每次重开都发
  /// 一个全新的 60min 自动结束窗口，窗口内幽灵按键（M500 ROM 双触发
  /// 漏键）把待继续 resume 成 running，关闭期间就被记成专注
  /// （用户实测「自动暂停后关闭软件，重开概率加上关闭时间」）。
  /// 持久化后宽限窗跨进程连续：暂停超 60min 后重开，首个 tick 即
  /// 自动最终结算结束会话，语义确定、关闭时间永不被计入。
  int? _pausedAtMillis;

  /// 进程最后一次确认存活的墙上时间戳（心跳，运行中每 10s 随周期结算落盘）。
  /// 恢复时用于 [TimerEngine.freezeForRestore] 扣除关机期间。
  int? _lastAliveAtMillis;

  /// 当前会话的开始墙上时间戳（会话落库用，US-D01）；
  /// 随 [_persist] 一并持久化，杀后台恢复后仍指向原始开始时刻。
  int? _sessionStartAtMillis;

  /// 当前会话在 drift 库中的行 id（R3 实时结算：每轮完成/暂停即 upsert
  /// 同一行，不再「结束才落库」）；新会话置 null 首结算时插入。
  /// 随 [_persist] 持久化，且每次结算后**立即**直写 prefs（不等 60s 节流），
  /// 杀后台恢复后续写同一行，不会重复计数。即便 id 丢失，落库层还会按
  /// startAt 找回同一行（[FocusSessionDao.settleSession]），双保险。
  int? _activeSessionId;

  /// 当前会话烙印的任务/标签（US-B05）：会话开始时从 currentTagProvider
  /// 捕获，之后改标签不回溯本会话；随 [_persist] 持久化，杀后台不丢。
  String? _sessionTag;

  /// 已结算入账的专注毫秒数；引擎累计超过它即触发一次结算（增量判定）。
  int _lastSettledFocusMillis = 0;

  /// 结算串行队列（R4）：所有 [_settle] 调用经 [_queueSettle] 排队执行。
  /// 裸 unawaited 时两个并发 settle 会同时看到 [_activeSessionId]==null
  /// 而各插一行 → 统计翻倍；串行后后一次必读到前一次写入的 id，只更新同一行。
  Future<void> _settleQueue = Future<void>.value();

  /// 周期结算节流时间戳（R5 近实时统计）：运行中的会话每
  /// [_kPeriodicSettleInterval] 入账一次（进行中专注按已做部分折算），
  /// 不再只等「轮完成/跳过/暂停/结束」四个事件点才入账。
  int? _lastPeriodicSettleAtMillis;
  static const _kPeriodicSettleInterval = Duration(seconds: 10);

  StreamSubscription<AppCommand>? _commandSub;
  Timer? _ticker;

  /// 「音乐下一首」转发的原生通道（MainActivity 侧
  /// AudioManager.dispatchMediaKeyEvent(KEYCODE_MEDIA_NEXT)）
  static const _mediaForwardChannel = MethodChannel('aiclock/media_forward');

  /// 当前心跳间隔（null = 停表）；[_syncTicker] 幂等管理
  Duration? _tickerInterval;

  /// App 是否处于后台（lifecycle 降频用，P2）
  bool _backgrounded = false;

  /// 上次 tick 触发视图刷新时的显示秒数（秒级去重，P0）
  int? _lastTickSecond;

  /// 上次 SharedPreferences 持久化时刻（结算路径 60s 节流的基准，P2）
  int? _lastPersistAtMillis;

  /// 前台心跳间隔
  static const _kTickForeground = Duration(milliseconds: 500);

  /// 后台心跳间隔（P2：通知为分钟级、计时免疫间隔，5s 足够驱动
  /// 阶段轮转/暂停释放/自动结束/周期结算）
  static const _kTickBackground = Duration(seconds: 5);

  /// 是否有进行中会话（运行或暂停；idle/completed = 无）。
  /// 心跳存在的唯一理由就是驱动会话，无会话必须停表（P0）。
  bool get _hasActiveSession =>
      (_engine.phase != TimerPhase.idle &&
          _engine.phase != TimerPhase.completed) ||
      _countUp.phase == CountUpPhase.running ||
      _countUp.phase == CountUpPhase.paused;

  /// 心跳管理（幂等）：有会话才运行；前台 500ms / 后台 5s。
  /// 在构造、每条命令、每次 tick、lifecycle 变化后调用。
  ///
  /// 2026-10-06 相位对齐：Timer.periodic 从「调用时刻」起算，tick 相位
  /// 随机落在秒周期内任意点——显示秒数在真实秒边界之后 0~500ms 才翻转，
  /// 肉眼即「辉光管刷新率不够、看着卡顿」。改为先把首个 tick 对齐到
  /// 墙壁时钟的周期边界（本毫秒取余补到下一个边界点），之后严格周期。
  void _syncTicker() {
    final Duration? desired = !_hasActiveSession
        ? null
        : _backgrounded
            ? _kTickBackground
            : _kTickForeground;
    if (desired == _tickerInterval) return;
    _tickerInterval = desired;
    _ticker?.cancel();
    _ticker = null;
    if (desired == null) return;
    final intervalMs = desired.inMilliseconds;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final delayMs = intervalMs - nowMs % intervalMs;
    void startPeriodic() {
      // 防御：对齐等待期间会话可能已结束（_syncTicker 被重入取消）
      if (_tickerInterval != desired) return;
      _ticker = Timer.periodic(desired, (_) => _onTick());
    }

    _ticker = Timer(
        Duration(milliseconds: delayMs <= 0 ? intervalMs : delayMs),
        startPeriodic);
  }

  /// 生命周期降频（P2）：切后台心跳 500ms→5s，回前台恢复。
  /// 计时精度不受影响（时间戳差值），阶段轮转最多晚到 5s 补齐。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final backgrounded = state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden;
    if (backgrounded == _backgrounded) return;
    _backgrounded = backgrounded;
    _syncTicker();
  }

  // ------------------------------------------------------------ 恢复与持久化

  /// 跨天僵尸会话守卫（真机反馈 R6）：恢复出的会话若开始于更早的本地日，
  /// 统计按 startAt 归属当日——继续 upsert 旧行会让「今天」的统计永远为零
  /// （用户实测：清数据后统计恢复记秒，根因即此）。
  /// 处理：先捕获旧会话快照并复位（昨天的「待继续」不该 resume 成今天的
  /// 会话），再把快照异步入账旧行——同一行覆盖，不双计、不丢历史。
  /// 必须在 restoredRunning/restoredPaused 判定之前调用。
  void _discardStaleDaySession() {
    final start = _sessionStartAtMillis;
    if (start == null) return;
    final hasSession = _engine.phase != TimerPhase.idle ||
        _countUp.phase != CountUpPhase.idle;
    if (!hasSession) return;
    if (isSameLocalDay(start, DateTime.now().millisecondsSinceEpoch)) return;
    // 关键顺序：先捕获快照（record + 行 id）再复位——
    // 异步写库若读复位后的引擎状态会拿到 0，导致旧行冲洗失败/双插新行
    final snapshot = _buildSessionRecord(isFinal: true);
    final sessionId = _activeSessionId;
    final tag = _sessionTag;
    _engine.reset();
    _countUp.reset();
    _sessionStartAtMillis = null;
    _activeSessionId = null;
    _sessionTag = null;
    _lastSettledFocusMillis = 0;
    unawaited(_persist());
    if (snapshot != null) {
      _settleQueue = _settleQueue
          .then((_) => _flushSnapshot(snapshot, sessionId: sessionId, tag: tag))
          .catchError((Object e) => debugPrint('settle failed: $e'));
    }
  }

  /// 关机/被杀期间不计入统计（用户口径）：恢复出「运行态」说明上次没有走
  /// 正常暂停退出（正常路径会先暂停），按被杀处理，把引擎冻结到最后存活时刻
  /// （[TimerEngine.freezeForRestore] / [CountUpTimer.freezeForRestore]）——
  /// 等价于在存活点暂停，重开需按键 resume 才继续。
  /// 同时把暂停基准置为存活时刻：关机超 60min 时首个心跳即自动最终结算结束
  /// 会话（复刻 R7/R9「关闭时间永不被计入」的语义）。
  void _freezeRestoredRunning() {
    final engineRunning = _engine.isRunning;
    final countUpRunning = _countUp.isRunning;
    if (!engineRunning && !countUpRunning) return;
    var frozen = false;
    if (engineRunning) {
      frozen = _engine.freezeForRestore(_lastAliveAtMillis) || frozen;
    }
    if (countUpRunning) {
      frozen = _countUp.freezeForRestore(_lastAliveAtMillis) || frozen;
    }
    if (!frozen) return;
    _pausedAtMillis = _lastAliveAtMillis ??
        DateTime.now().millisecondsSinceEpoch;
    unawaited(_persist());
  }

  /// 启动自愈 + 活跃行找回：
  /// 1. 找回活跃会话行 id（prefs 里的 id 可能因「结算后立即被杀」的窗口期丢失）
  ///    —— 用会话开始时刻在库里定位同一行，避免后续结算插入重复行；
  /// 2. 关闭悬空「进行中」孤儿行（endAt 回填 startAt + actualFocusMillis）；
  /// 3. 删除重复落库的会话行（同 (startAt, mode) 只留 actual 最大者）；
  /// 4. 删除物理不可能的幽灵行（actual 超出行跨度 65s 以上）。
  /// 当前活跃会话行不触碰。有任何修复动作则刷新统计页。
  Future<void> _recoverAndRepair() async {
    try {
      final dao = _ref.read(appDatabaseProvider).focusSessionDao;
      await _recoverActiveSessionId(dao);
      final closed =
          await dao.closeOrphanOpenSessions(exceptId: _activeSessionId);
      final dup = await dao.deleteDuplicateSessions(keepId: _activeSessionId);
      final deleted = await dao.deleteImpossibleSessions();
      if (closed > 0 || dup > 0 || deleted > 0) {
        debugPrint(
            'session repair: closed=$closed dup=$dup deleted=$deleted');
        _invalidateStats();
      }
    } catch (e) {
      debugPrint('session repair failed: $e');
    }
  }

  /// 用会话开始时刻在库里找回活跃行 id（同会话开始时刻唯一且不变）。
  /// 找到且与当前缓存不一致时立即直写 prefs，供后续结算/守卫使用。
  Future<void> _recoverActiveSessionId(FocusSessionDao dao) async {
    final start = _sessionStartAtMillis;
    if (start == null) return;
    final hasSession = _engine.phase != TimerPhase.idle ||
        _countUp.phase != CountUpPhase.idle;
    if (!hasSession) return;
    final row = await dao.sessionByStartAt(start);
    if (row == null || row.id == _activeSessionId) return;
    _activeSessionId = row.id;
    await _prefs.setInt(_kSessionId, row.id);
  }

  /// 杀后台恢复：从 SharedPreferences 读回番茄引擎状态。
  /// 引擎记录的是墙上时间戳，进程死亡期间流逝的时间会在下一次
  /// tick 自动补齐（例如死亡期间专注已结束，会自动轮转到休息）。
  TimerEngine? _restoreEngine() {
    final raw = _prefs.getString(_kEngineState);
    if (raw == null) return null;
    try {
      return TimerEngine.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } on FormatException {
      return null; // 数据损坏则放弃恢复
    }
  }

  /// 读回正计时状态。运行态恢复后死亡期间时间自动计入（人在工作，计时不该丢）。
  CountUpTimer? _restoreCountUp() {
    final raw = _prefs.getString(_kCountUpState);
    if (raw == null) return null;
    try {
      return CountUpTimer.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } on FormatException {
      return null;
    }
  }

  /// 节流持久化（P2）：距上次 [_persist] 不足 60s 则跳过。
  /// 仅周期结算等高频路径使用——崩溃恢复的游标精度损失 ≤1 分钟，可接受；
  /// 命令/阶段轮转等关键路径仍直接 [_persist] 立即落盘。
  void _persistThrottled() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastPersistAtMillis;
    if (last != null &&
        now - last < const Duration(seconds: 60).inMilliseconds) {
      return;
    }
    unawaited(_persist());
  }

  /// 每次状态变化后持久化（两个引擎各自独立键 + 会话开始时刻 + 结算游标）。
  Future<void> _persist() async {
    _lastPersistAtMillis = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(_kEngineState, jsonEncode(_engine.toJson()));
    await _prefs.setString(_kCountUpState, jsonEncode(_countUp.toJson()));
    final start = _sessionStartAtMillis;
    if (start == null) {
      await _prefs.remove(_kSessionStart);
    } else {
      await _prefs.setInt(_kSessionStart, start);
    }
    final sessionId = _activeSessionId;
    if (sessionId == null) {
      await _prefs.remove(_kSessionId);
    } else {
      await _prefs.setInt(_kSessionId, sessionId);
    }
    final tag = _sessionTag;
    if (tag == null) {
      await _prefs.remove(_kSessionTag);
    } else {
      await _prefs.setString(_kSessionTag, tag);
    }
    if (_activeSessionId == null && _lastSettledFocusMillis == 0) {
      await _prefs.remove(_kSettledFocus);
    } else {
      await _prefs.setInt(_kSettledFocus, _lastSettledFocusMillis);
    }
    final pausedAt = _pausedAtMillis;
    if (pausedAt == null) {
      await _prefs.remove(_kPausedAt);
    } else {
      await _prefs.setInt(_kPausedAt, pausedAt);
    }
    final aliveAt = _lastAliveAtMillis;
    if (aliveAt == null) {
      await _prefs.remove(_kLastAlive);
    } else {
      await _prefs.setInt(_kLastAlive, aliveAt);
    }
  }

  // ------------------------------------------------------------ 命令处理

  void _onCommand(AppCommand rawCommand) {
    // 模式分发：上一曲在正计时下改写为打点；无阶段概念的操作降级 ignored。
    final command = resolveForMode(rawCommand, _mode);
    // 反馈先行：先发出声音确认（<100ms 感知延迟的关键），再执行命令。
    _playFeedbackFor(command);
    switch (command) {
      case AppCommand.toggleStartPause:
        _toggleStartPause();
      case AppCommand.addFiveMinutes:
        _engine.addTime(const Duration(minutes: 5));
      case AppCommand.skipPhase:
        _engine.skipPhase();
        // R4 语义：跳过休息会停在专注起点（待继续暂停态），
        // 纳入暂停超时释放与实时结算；跳过专注则自动进休息（不停顿）
        // R14：切换阶段是事件点——立即结算并把 10s 周期窗归零重数
        if (_engine.phase == TimerPhase.paused) {
          _onSessionPause(); // 内部已立即结算 + 重置窗口
        } else {
          _settleNowAndResetWindow();
        }
      case AppCommand.finishSession:
        _finish();
      case AppCommand.tickMark:
        _countUp.addMark();
      case AppCommand.forwardNext:
        unawaited(_forwardNextToMusic());
      case AppCommand.ignored:
        break;
    }
    _emit(lastCommand: command);
    unawaited(_persist());
    _syncTicker(); // 命令可能开始/结束会话（P0：无会话停表）
  }

  /// 把 AppCommand 结合当前引擎状态解释成反馈事件并播放。
  /// 未映射/当前模式下无效果的按键（ignored）不给反馈——避免误以为生效。
  void _playFeedbackFor(AppCommand command) {
    final event = switch (command) {
      AppCommand.toggleStartPause => _toggleFeedbackEvent(),
      AppCommand.addFiveMinutes || AppCommand.tickMark => FeedbackEvent.mark,
      AppCommand.skipPhase => FeedbackEvent.skip,
      AppCommand.finishSession => FeedbackEvent.end,
      // 转发给音乐 App：用 skip 音型（「下一首」与「跳过」同为前进语义）
      AppCommand.forwardNext => FeedbackEvent.skip,
      AppCommand.ignored => null,
    };
    if (event == null) return;
    // 自定义提示音（2026-10-05）：按槽位键（内置音型资产路径）查用户配置
    final assetKey = FeedbackPolicy.toneAssetFor(event);
    _ref.read(keyFeedbackServiceProvider).play(
          event,
          _ref.read(keyFeedbackSettingsProvider),
          custom: _ref.read(customTonesProvider)[assetKey],
        );
  }

  /// 「音乐下一首」转发（默认双按绑定）。
  ///
  /// 硬路径优先（看板 #38）：授权「通知读取」后经 MediaSessionManager
  /// 直控外部媒体会话 skipToNext()，绕过 M500 ROM 的媒体键路由
  /// （软路径 dispatchMediaKeyEvent 真机实测无效）。硬路径不经系统
  /// 路由，**无需释放按键**——keep-alive 不打断、无重霸占窗口。
  /// 失败回退软路径：释放 → dispatch → 延时重霸占。
  /// 按键未接管时无需转发（物理键本来就直接到达音乐 App）。
  Future<void> _forwardNextToMusic() async {
    if (!_handler.keysAcquired) return;
    // 防回环：转发的 NEXT 若被 ROM 路由回本 App（我们仍是顶层
    // MediaSession 时会发生），handler 在窗口内吞掉它
    _handler.ignoreNextUntilMillis =
        DateTime.now().millisecondsSinceEpoch + 1500;
    try {
      final direct = await _mediaForwardChannel
          .invokeMethod<bool>('dispatchNextDirect');
      if (direct ?? false) return; // 直达成功：保持霸占，立即返回
    } on MissingPluginException {
      // 测试/非 Android 环境无原生侧：继续走软路径（同样静默）
    }
    await _handler.releaseKeys();
    try {
      await _mediaForwardChannel.invokeMethod<void>('dispatchNext');
    } on MissingPluginException {
      // 测试/非 Android 环境无原生侧：静默降级
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    // 会话仍在且开关允许 → 重新霸占（期间若用户结束会话则不再抢回）
    if (_handler.sessionActive && _ref.read(keysTakeoverProvider)) {
      await _handler.acquireKeys();
    }
  }

  /// 「单按」三态切换对应的反馈事件：开始 / 继续 / 暂停。
  FeedbackEvent _toggleFeedbackEvent() {
    if (_mode == TimerMode.countUp) {
      return switch (_countUp.phase) {
        CountUpPhase.idle || CountUpPhase.finished => FeedbackEvent.start,
        CountUpPhase.paused => FeedbackEvent.resume,
        CountUpPhase.running => FeedbackEvent.pause,
      };
    }
    return switch (_engine.phase) {
      TimerPhase.idle || TimerPhase.completed => FeedbackEvent.start,
      TimerPhase.paused => FeedbackEvent.resume,
      _ => FeedbackEvent.pause,
    };
  }

  /// 触屏备用按钮与「单按」共用的三态切换。
  void _toggleStartPause() {
    if (_mode == TimerMode.countUp) {
      switch (_countUp.phase) {
        case CountUpPhase.idle:
        case CountUpPhase.finished:
          _countUp.start();
          _onSessionEnter();
        case CountUpPhase.running:
          _countUp.pause();
          _onSessionPause();
        case CountUpPhase.paused:
          _countUp.resume();
          _onSessionResume();
      }
      return;
    }
    switch (_engine.phase) {
      case TimerPhase.idle:
      case TimerPhase.completed:
        _engine.start();
        _onSessionEnter();
      case TimerPhase.focusing:
      case TimerPhase.shortBreak:
      case TimerPhase.longBreak:
        _engine.pause();
        _onSessionPause();
      case TimerPhase.paused:
        _engine.resume();
        _onSessionResume();
    }
  }

  /// 进入计时：按开关决定是否霸占按键。
  /// 新会话在此刻开始，记录开始时间戳（US-D01 落库用）并重置结算游标（R3）。
  void _onSessionEnter() {
    _pausedAtMillis = null;
    _sessionStartAtMillis = DateTime.now().millisecondsSinceEpoch;
    _lastAliveAtMillis = _sessionStartAtMillis; // 心跳起点（关机冻结基准）
    _activeSessionId = null;
    _sessionTag = _ref.read(currentTagProvider); // 烙印当前标签（US-B05）
    _lastSettledFocusMillis = 0;
    _lastPeriodicSettleAtMillis = null;
    _handler.sessionActive = true;
    if (_ref.read(keysTakeoverProvider)) {
      unawaited(_handler.acquireKeys());
    }
  }

  /// 进入暂停：记录暂停时刻，供超时释放判定（US-C02）；
  /// 顺手做一次进行中结算（R3：暂停是天然的崩溃安全点）。
  void _onSessionPause() {
    _pausedAtMillis = DateTime.now().millisecondsSinceEpoch;
    // 心跳对齐到暂停时刻并**立即单键落盘**（R12）：暂停后若进程被强杀且
    // 引擎状态那次异步落盘没赶上，恢复冻结会以心跳为基准——心跳陈旧
    // （只由 10s 周期结算推进）会吞掉「暂停前已做但未结算」的专注，
    // 用户实测「已暂停才关机，却只记上一点点」。单 int 写入比整份
    // _persist()（8 次 await）快得多，先抢在关机前落盘。
    // R14：暂停还是事件点——立即结算并把 10s 周期窗归零重数。
    _settleNowAndResetWindow();
  }

  /// 从暂停恢复：若此前因超时被释放了按键，重新霸占；宽限窗清零。
  void _onSessionResume() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _pausedAtMillis = null;
    // 恢复后进程重新存活：心跳前移到此刻，减少后续被强杀时冻结的误差。
    _lastAliveAtMillis = now;
    // R14：恢复同属事件点——10s 周期窗从按下时刻起重新数。
    _lastPeriodicSettleAtMillis = now;
    if (_ref.read(keysTakeoverProvider) && !_handler.keysAcquired) {
      unawaited(_handler.acquireKeys());
    }
  }

  /// 结束会话：先把引擎状态折算为最终结算（必须在 finish 之前取快照），
  /// 再结束引擎、释放按键还给系统音乐 App。
  ///
  /// R8 修复（统计翻倍根因）：旧实现先 `_queueSettle(isFinal: true)` 再
  /// 同步清游标——队列化的 settle 在微任务里执行，读到的是**清零后**的
  /// 游标：startAt 退化为 now（0 时长幽灵行）、id 为 null（新插行而非更新），
  /// 真行永远不被关闭（保持「进行中」），真行+幽灵行 = 统计翻倍。
  /// 现与 R6 守卫同一模式：先捕获快照+行 id，再清游标，最后异步入账。
  void _finish() {
    _pausedAtMillis = null;
    final snapshot = _buildSessionRecord(isFinal: true);
    final sessionId = _activeSessionId;
    final tag = _sessionTag;
    if (_mode == TimerMode.countUp) {
      _countUp.finish();
    } else {
      _engine.finish();
    }
    _sessionStartAtMillis = null;
    _activeSessionId = null;
    _sessionTag = null;
    _lastSettledFocusMillis = 0;
    _lastPeriodicSettleAtMillis = null;
    _handler.sessionActive = false;
    unawaited(_handler.releaseKeys());
    if (snapshot != null) {
      _settleQueue = _settleQueue
          .then((_) => _flushSnapshot(snapshot, sessionId: sessionId, tag: tag))
          .catchError((Object e) => debugPrint('settle failed: $e'));
    }
    // 自动结束（R7）路径不会经 _onCommand，必须自己持久化游标清理，
    // 否则杀后台后恢复出过期 sessionId，后续结算写进已关闭行（R8）
    unawaited(_persist());
  }

  /// 把当前引擎状态折算为会话记录；实际专注为 0 时返回 null（不落库）。
  /// [isFinal]=false 表示进行中结算：completed=false、endAt 由落库层置 null。
  FocusSessionRecord? _buildSessionRecord({required bool isFinal}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    // 恢复边界：开始时刻丢失时用「结束时刻 - 实际专注」回推，保证区间合法。
    // 番茄优先取最早专注段起点——比 startAt=now 更真实，也避免被启动自愈
    // 的「物理不可能行」（actual 超出行跨度）误删导致统计归零。
    var start = _sessionStartAtMillis;
    if (start == null && _mode == TimerMode.pomodoro) {
      final segs = _engine.focusSegments;
      if (segs.isNotEmpty) start = segs.first.$1;
    }
    // 专注段的实际结束时刻（R12）：暂停中取「最后一次活动时刻」（未闭合暂停的
    // 起点），运行中即 now。恢复冻结/跨天冲刷时 now 是重开进程的时刻，若拿它当
    // 段终点，会把一段真实专注在时间轴上拉成跨越关机的大块（用户实测
    // 「统计轴显示从昨日 21:30 到今天开机 11:41 一整段番茄」）。
    final activeFocusEnd = _activeFocusEndMillis(now);
    if (_mode == TimerMode.countUp) {
      final record = SessionRecordBuilder.fromCountUp(
        startAtMillis: start ?? now - _countUp.elapsed.inMilliseconds,
        endAtMillis: now,
        activeFocusEndMillis: activeFocusEnd,
        elapsed: _countUp.elapsed,
        marks: _countUp.marks,
        pauses: _countUp.pauses,
        completed: isFinal,
      );
      return record;
    }
    return SessionRecordBuilder.fromPomodoro(
      startAtMillis: start ?? now,
      endAtMillis: now,
      completedRounds: _engine.completedFocusRounds,
      accumulatedFocusMillis: _engine.accumulatedFocusMillis,
      config: _engine.config,
      phase: _engine.phase,
      phaseBeforePause: _engine.phaseBeforePause,
      // R9 以计时为主：进行中段的已做时长由引擎按墙钟区间计算，
      // 不再用「计划时长 - 剩余」折算（addTime 加时会污染该折算）
      currentFocusDoneMillis: _engine.currentFocusDoneMillis,
      currentFocusStartedAtMillis: _engine.phaseStartedAtMillis,
      activeFocusEndMillis: activeFocusEnd,
      focusSegments: _engine.focusSegments,
      pauses: _engine.pauses,
      completed: isFinal,
    );
  }

  /// 专注段的实际结束时刻（R12）：暂停中取未闭合暂停的起点（暂停发生时刻），
  /// 运行中即 [now]。用于修正恢复冻结/跨天冲刷时用「重开时刻」当段终点导致的
  /// 时间轴虚长。休息阶段的暂停不记暂停（引擎语义），故休息态回退 [now]。
  int _activeFocusEndMillis(int now) {
    final pauses =
        _mode == TimerMode.countUp ? _countUp.pauses : _engine.pauses;
    for (var i = pauses.length - 1; i >= 0; i--) {
      if (pauses[i].$2 == null) {
        final at = pauses[i].$1;
        return at < now ? at : now;
      }
    }
    return now;
  }

  /// 由记录构建落库 companion（[_settle] 与跨天守卫共用）。
  /// 不带 id——行身份由 [FocusSessionDao.settleSession] 按 sessionId/startAt 解析
  /// （id 丢失时按 startAt 找回同一行，杜绝重复行）。
  /// [isFinal] 为 true 时写 endAt（进行中结算保持 endAt=null 表语义）。
  /// [tag] 为会话开始时的烙印标签（US-B05）——快照冲刷路径必须在清游标
  /// 前捕获传入，此处不读字段（避免异步执行时读到已清零的值，R8 同类坑）。
  FocusSessionsCompanion _companionOf(
    FocusSessionRecord record, {
    required bool isFinal,
    String? tag,
  }) {
    return FocusSessionsCompanion(
      startAt: Value(record.startAtMillis),
      endAt: isFinal ? Value(record.endAtMillis) : const Value(null),
      plannedFocusMillis: Value(record.plannedFocusMillis),
      actualFocusMillis: Value(record.actualFocusMillis),
      rounds: Value(record.rounds),
      completed: Value(record.completed),
      mode: Value(record.mode.storageKey),
      // 打点（US-B02 复盘）：JSON 偏移毫秒数组；无打点写 null
      marksJson: Value(record.marks.isEmpty
          ? null
          : jsonEncode(record.marks.map((m) => m.inMilliseconds).toList())),
      // 专注段区间（R8 时间轴断断续续渲染）：JSON [[start,end],...]；空写 null
      intervalsJson: Value(record.focusSegments.isEmpty
          ? null
          : jsonEncode(
              <List<int>>[for (final s in record.focusSegments) [s.$1, s.$2]])),
      // 中断区间（US-D02）：JSON [[start,endOrNull],...]；空写 null
      pausesJson: Value(record.pauses.isEmpty
          ? null
          : jsonEncode(
              <List<int?>>[for (final p in record.pauses) [p.$1, p.$2]])),
      // 任务/标签（US-B05）：会话开始时烙印；无标签写 null
      tag: Value(tag),
    );
  }

  /// 结算统计页数据源刷新（今日/本周/连续/周报/热力图/详细页/当日小结）。
  ///
  /// 2026-09-25 补：原清单漏了 `daySessionsProvider` 与 `dailySummaryProvider`
  /// （详细页时间轴与「当日小结」卡、以及 AI 当日点评的数据源），
  /// 结算后不刷新 → 详细页与当日点评长期读到结算前的旧数据（08-A2 的
  /// 数据指纹也因此永远检测不到变化）。family provider 直接 invalidate
  /// 全组合失效（同 settings_page 的既有姿势）。
  ///
  /// 注：`weeklyInsightProvider`（AI 周报解读）**依赖 `streakProvider`**，
  /// 故靠失效级联自动重算，不在此单列——避免 focus → ai 的 features
  /// 横向依赖（§6-47(b)）。改 weeklyInsightProvider 的依赖时需回看此处。
  void _invalidateStats() {
    _ref
      ..invalidate(todayFocusProvider)
      ..invalidate(todayRoundsProvider)
      ..invalidate(weekFocusProvider)
      ..invalidate(streakProvider)
      ..invalidate(weeklyReportProvider)
      ..invalidate(heatmapProvider)
      ..invalidate(daySessionsProvider)
      ..invalidate(dailySummaryProvider);
  }

  /// 实时结算（R3）：把当前会话状态 upsert 到 drift 同一行——
  /// 每轮自然完成、跳过、暂停时增量入账，统计页当日即可见，
  /// 不再「结束才落库」（旧行为下一整天自动续轮 = 永不结束 = 统计为零）。
  /// [isFinal] 为 true 时写 endAt 且 completed=true（用户主动结束）。
  ///
  /// 调用方一律走 [_queueSettle] 串行排队，禁止直接并发调用（R4：
  /// 并发 settle 会双插行导致统计翻倍）。
  Future<void> _settle({required bool isFinal}) async {
    final record = _buildSessionRecord(isFinal: isFinal);
    if (record == null) return; // 实际专注仍为 0，无可入账
    final db = _ref.read(appDatabaseProvider);
    _activeSessionId = await db.focusSessionDao.settleSession(
      _companionOf(record, isFinal: isFinal, tag: _sessionTag),
      sessionId: _activeSessionId,
    );
    // 行 id 立即直写 prefs（不等 60s 节流）：首结算插入新行后若被杀的窗口期
    // 内丢 id，重开会按 startAt 重插一行造成统计翻倍——此处消除该窗口。
    if (!isFinal) {
      await _prefs.setInt(_kSessionId, _activeSessionId!);
      _lastSettledFocusMillis = record.actualFocusMillis;
      _persistThrottled(); // P2：周期结算 10s 一次，SP 写入节流为 60s
    }
    _invalidateStats();
  }

  /// 写入一份**预构建快照**（跨天僵尸会话守卫专用）：调用方在复位引擎前
  /// 已捕获 record 与 sessionId，此处只写库、不读不改控制器游标。
  Future<void> _flushSnapshot(
    FocusSessionRecord record, {
    int? sessionId,
    String? tag,
  }) async {
    final db = _ref.read(appDatabaseProvider);
    await db.focusSessionDao.settleSession(
      _companionOf(record, isFinal: true, tag: tag),
      sessionId: sessionId,
    );
    _invalidateStats();
  }

  /// 结算入队：把一次 [_settle] 追加到串行队列尾部，立即返回（fire-and-forget）。
  /// 队列内任何一次失败只记日志，不阻断后续结算。
  void _queueSettle({required bool isFinal}) {
    _settleQueue = _settleQueue
        .then((_) => _settle(isFinal: isFinal))
        .catchError((Object e) => debugPrint('settle failed: $e'));
  }

  /// 增量结算判定：引擎真实累计超过已入账值即结算（每轮完成/跳过后调用）。
  void _settleIfAccumulated() {
    if (_engine.accumulatedFocusMillis > _lastSettledFocusMillis) {
      _queueSettle(isFinal: false);
    }
  }

  /// 事件点结算（R14）：暂停 / 终止 / 切换阶段 / 恢复等指令按下时**立即**
  /// 入账一次，并把 10s 周期结算窗**归零重数**（从按下时刻起再数 10s）。
  ///
  /// 目的：让「按下那一刻」就是确认点——已确认数据立即持久，不依赖下一次
  /// 周期 tick；同时把心跳前移到此刻，缩小被强杀时的冻结误差（R12）。
  /// 写侧另有高水位保证（R13），已确认数据不会被任何形式的更小值覆盖。
  void _settleNowAndResetWindow() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _lastPeriodicSettleAtMillis = nowMs;
    _lastAliveAtMillis = nowMs;
    unawaited(_prefs.setInt(_kLastAlive, nowMs));
    _queueSettle(isFinal: false);
  }

  // ------------------------------------------------------------ 心跳与刷新

  void _onTick() {
    // 番茄引擎始终 tick（即使当前查看正计时——模式切换置灰保证
    // 番茄有进行中会话时不会切走，此处仅兜底恢复边界）。
    final changed = _engine.tick();
    if (changed) {
      // 阶段自然轮转（专注→休息、休息→专注）：熄屏提醒，US-F01。
      // 看板 #47：自然进入长休（四轮完成）改放庆祝音，替代本次提醒音
      final event = _engine.phase == TimerPhase.longBreak
          ? FeedbackEvent.celebrate
          : FeedbackEvent.phaseChange;
      _ref.read(keyFeedbackServiceProvider).play(
            event,
            _ref.read(keyFeedbackSettingsProvider),
            custom: _ref
                .read(customTonesProvider)[FeedbackPolicy.toneAssetFor(event)],
          );
      // R4 语义：专注结束自动进休息（继续运行）；休息结束才停在
      // 下一段专注起点（待继续暂停态），纳入暂停超时释放（R3）
      if (_engine.phase == TimerPhase.paused) _onSessionPause();
      _settleIfAccumulated(); // 每轮自然完成即结算入账（R3）
      unawaited(_persist());
    }
    final released = _checkPauseTimeout();
    _checkAutoFinish();
    _maybePeriodicSettle();
    // 秒级去重（性能 P0）：显示秒数未变且无阶段轮转/按键释放时不刷新视图——
    // 运行中约 1Hz 刷新、暂停态零刷新（旧实现每 500ms 整树 rebuild）。
    final second = _mode == TimerMode.countUp
        ? _countUp.elapsed.inSeconds
        : _engine.remaining.inSeconds;
    if (changed || released || second != _lastTickSecond) {
      _lastTickSecond = second;
      _emit();
    }
    _syncTicker(); // 自动结束/阶段轮转可能让会话终止（P0：无会话停表）
  }

  /// 不活跃自动结束（真机反馈 R7）：暂停/待继续超过 60 分钟 →
  /// 结束整个会话（最终结算 + 复位 + 释放按键 + 通知回「准备开始」）。
  /// 背景：M500 ROM 媒体键双触发（保留项）会把音乐 App 的按键漏进本 App，
  /// 无限期的「待继续」会被幽灵按键一轮轮 resume 出假统计（实测 +2h）。
  /// 阈值固定 60 分钟：远长于正常轮间歇、远短于离开半天；
  ///  [_finish] 内部已做最终结算，历史不丢。
  void _checkAutoFinish() {
    final pausedAt = _pausedAtMillis;
    if (pausedAt == null) return;
    final isPaused = _engine.phase == TimerPhase.paused ||
        _countUp.phase == CountUpPhase.paused;
    if (!isPaused) return;
    if (PauseReleasePolicy.shouldAutoFinish(
      pausedAtMillis: pausedAt,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
      threshold: PauseReleasePolicy.defaultAutoFinishThreshold,
    )) {
      _finish();
    }
  }

  /// 周期结算（R5 近实时统计）：会话运行中（番茄含休息阶段 / 正计时）
  /// 每 [_kPeriodicSettleInterval] upsert 一次同一行，统计页接近实时可见。
  /// 与事件点结算（轮完成/跳过/暂停/结束）共用串行队列，天然防并发双插。
  void _maybePeriodicSettle() {
    if (!(_engine.isRunning || _countUp.isRunning)) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final last = _lastPeriodicSettleAtMillis;
    if (last != null &&
        nowMs - last < _kPeriodicSettleInterval.inMilliseconds) {
      return;
    }
    _lastPeriodicSettleAtMillis = nowMs;
    // 存活心跳落盘（单 int，10s 一次）：恢复时据此扣除关机期间，越界误差 ≤10s
    _lastAliveAtMillis = nowMs;
    unawaited(_prefs.setInt(_kLastAlive, nowMs));
    _queueSettle(isFinal: false);
  }

  /// 暂停超时检查（US-C02）：暂停超过阈值且仍持有按键 → 释放 MediaSession
  /// 归还音乐 App，专注记录不作废；用户继续时经 [_onSessionResume] 重新霸占。
  /// 返回本次是否发生了释放（释放改变 keysAcquired，需触发一次视图刷新）。
  bool _checkPauseTimeout() {
    final pausedAt = _pausedAtMillis;
    if (pausedAt == null || !_handler.keysAcquired) return false;
    final threshold = _ref.read(pauseReleaseThresholdProvider);
    if (PauseReleasePolicy.shouldRelease(
      pausedAtMillis: pausedAt,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
      threshold: threshold,
    )) {
      unawaited(_handler.releaseKeys());
      return true;
    }
    return false;
  }

  void _emit({AppCommand? lastCommand}) {
    state = state.copyWith(
      mode: _mode,
      phase: _engine.phase,
      phaseBeforePause: _engine.phaseBeforePause,
      remaining: _engine.remaining,
      phaseTotal: _engine.currentPhaseTotal,
      completedRounds: _engine.completedFocusRounds,
      countUpPhase: _countUp.phase,
      elapsed: _countUp.elapsed,
      markCount: _countUp.marks.length,
      keysAcquired: _handler.keysAcquired,
      lastCommand: lastCommand,
    );
    _pushNotificationDisplay();
  }

  /// 通知栏显示推送（US-F02/F03）：阶段 + 剩余/累计时间——
  /// 签名未变时不重复调用平台侧（_emit 每 500ms 一次）。
  /// 时间为分钟级（真机反馈 R2：M500 ROM 对每次 notify() 整窗重绘，
  /// 秒级文本会让整个通知每秒闪烁；分钟级把刷新降到每分钟一次）。
  /// 显示归属控制器：无会话 → 「准备开始」；有会话（含暂停超时释放后）
  /// → 当前模式的阶段与时间，不再受按键接管状态影响。
  void _pushNotificationDisplay() {
    final sessionActive = _mode == TimerMode.countUp
        ? (_countUp.isRunning || _countUp.phase == CountUpPhase.paused)
        : (_engine.isRunning || _engine.phase == TimerPhase.paused);
    if (!sessionActive) {
      if (_displaySignature != 'idle') {
        _displaySignature = 'idle';
        _handler.showIdleDisplay();
      }
      return;
    }
    final (label, timeText, running) = switch (_mode) {
      TimerMode.pomodoro => (
          _engine.phase.label,
          // 通知第二行：阶段进度 + 轮次（idle/completed 给语义化文案）
          switch (_engine.phase) {
            TimerPhase.idle => '准备开始',
            TimerPhase.completed =>
              '本轮会话已结束 · 共 ${_engine.completedFocusRounds} 轮',
            _ => '剩 ${formatRemainingMinutes(_engine.remaining)}'
                ' · 第 ${_engine.completedFocusRounds + 1} 轮',
          },
          _engine.isRunning,
        ),
      TimerMode.countUp => (
          _countUp.phase.label,
          switch (_countUp.phase) {
            CountUpPhase.idle => '准备开始',
            CountUpPhase.finished =>
              '已结束 · 共 ${formatElapsedMinutes(_countUp.elapsed)}',
            _ => '已计 ${formatElapsedMinutes(_countUp.elapsed)}'
                '${_countUp.marks.isNotEmpty ? ' · 打点 ${_countUp.marks.length} 个' : ''}',
          },
          _countUp.isRunning,
        ),
    };
    final signature = '$label|$timeText|$running';
    if (signature == _displaySignature) return;
    _displaySignature = signature;
    _handler.updateTimerDisplay(
        phaseLabel: label, timeText: timeText, running: running);
  }

  /// 上次推送到通知的显示签名（节流用）
  String? _displaySignature;

  // ------------------------------------------------------------ 触屏备用入口

  /// 主界面大按钮：与「单按」同语义。
  void tapPrimaryButton() => _onCommand(AppCommand.toggleStartPause);

  /// 触屏侧键「+5 分钟」（看板 #56）：与实体「上一曲」同一条命令总线，
  /// 正计时模式下由 [resolveForMode] 自动改写为打点——语义永远与按键一致。
  void addFiveMinutes() => _onCommand(AppCommand.addFiveMinutes);

  /// 触屏「终止」（竖屏左下角方块，2026-10-05）：与实体「长按」同语义，
  /// 结束当前会话并保存记录（弹性中断：记录不作废）。
  void finishSession() => _onCommand(AppCommand.finishSession);

  /// 触屏「下一阶段」（竖屏右下角方块，2026-10-06）：与实体「下一曲」
  /// 同一条命令总线——番茄 = 跳过当前阶段，正计时 = 打点降级。
  void skipPhase() => _onCommand(AppCommand.skipPhase);

  /// 切换计时模式。仅当两种模式都无进行中会话时生效（返回是否成功）。
  Future<bool> setMode(TimerMode mode) async {
    if (mode == _mode) return true;
    if (state.sessionActive) return false; // 有进行中会话，拒绝切换
    _mode = mode;
    await _ref.read(timerModeProvider.notifier).setMode(mode);
    _emit();
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_commandSub?.cancel());
    _ticker?.cancel();
    super.dispose();
  }
}
