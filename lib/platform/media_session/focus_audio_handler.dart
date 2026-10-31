/// 媒体按键处理器：霸占 MediaSession、把实体按键转成语义事件发给 CommandBus。
///
/// ── M500 直连场景说明 ─────────────────────────────────────────────
/// M500 侧边实体键为主板直连，出厂映射标准媒体键码
/// （上一曲 88 / 播放暂停 85 / 下一曲 87），事件通过
/// MediaButtonReceiver 直达当前活跃 MediaSession，时序稳定、无丢键，
/// 因此本文件不包含任何蓝牙 AVRCP 兼容/补发逻辑。
///
/// 核心策略：与「M500 系统音乐 App」抢按键。
/// - [acquireKeys]：开始专注时调用。激活本 App 的 AudioSession 并循环
///   播放静音 keep-alive，让 MediaSession 保持 playing 态，实体按键
///   全部路由到本 App。
/// - [releaseKeys]：结束/退出时调用。停静音并 setActive(false)，
///   把按键交还给系统音乐 App。
///
/// 通知职责（US-F02/US-F03）：霸占期间 MediaStyle 通知显示当前阶段与
/// 剩余时间，并提供「暂停/继续」「结束」「跳过」按钮。
/// ─────────────────────────────────────────────────────────────────
library;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/commands/app_command.dart';
import '../../core/media/media_key_event.dart';

/// BaseAudioHandler 实现：语义回调（play/pause/skipToNext/skipToPrevious）
/// → 多击计数（300ms 窗）→ MediaKeyEvent → CommandBus。
class FocusAudioHandler extends BaseAudioHandler {
  FocusAudioHandler({required CommandBus commandBus})
      : _commandBus = commandBus {
    _grouper = ClickGrouper(onResolved: _commandBus.dispatchKey);
  }

  final CommandBus _commandBus;
  late final ClickGrouper _grouper;

  /// 静音 keep-alive 播放器（循环播放 assets/audio/silence.wav，2 分钟@8kHz）
  final AudioPlayer _player = AudioPlayer();

  AudioSession? _session;

  /// 当前是否已接管实体按键（供 UI 显示状态）
  bool keysAcquired = false;

  /// 是否有进行中的计时会话（由 FocusController 维护）。
  ///
  /// 与 [keysAcquired] 的区别：暂停超时后按键已归还（未接管），但会话
  /// 仍在——此间通知栏按钮（播放/结束）必须保持可用，用户才能
  /// 「一键重新接管」（US-C02）。
  bool sessionActive = false;

  /// 语义回调准入：未接管且无语会话时按键属于系统音乐 App，不响应。
  bool get _shouldHandleKeys => keysAcquired || sessionActive;

  /// 初始化：配置音频会话、加载静音资源。App 启动时调用一次。
  Future<void> init() async {
    _session = await AudioSession.instance;
    // music 配置：申请音频焦点走媒体通道，符合系统对「播放器」的预期
    await _session!.configure(const AudioSessionConfiguration.music());
    await _player.setAsset('assets/audio/silence.wav');
    await _player.setLoopMode(LoopMode.one);
    await _player.setVolume(0); // 双保险：内容本身静音，音量也归零

    // 让锁屏/通知有内容可显示（否则部分 ROM 不下发按键事件）
    showIdleDisplay();
  }

  /// 接管实体按键：激活 MediaSession + 播放静音 keep-alive。
  Future<void> acquireKeys() async {
    final session = _session;
    if (session == null || keysAcquired) return;
    await session.setActive(true);
    await _player.play(); // 保持 playing 态，按键才会持续路由过来
    keysAcquired = true;
  }

  /// 释放实体按键：停静音、AudioSession setActive(false)，还给系统音乐 App。
  /// 注意不改动通知显示——显示内容由 FocusController 统一驱动
  /// （暂停超时释放后通知仍显示「已暂停」，而非错误的「准备开始」）。
  Future<void> releaseKeys() async {
    final session = _session;
    if (session == null || !keysAcquired) return;
    await _player.pause();
    await session.setActive(false);
    keysAcquired = false;
  }

  // ------------------------------------------------------------ 通知显示

  /// 空闲态通知内容（未计时/已结束）。由 FocusController 在无会话时调用。
  void showIdleDisplay() {
    _lastNotifiedRunning = null; // 下次计时显示必须重发 playbackState
    mediaItem.add(const MediaItem(
      id: 'ai_clock_focus',
      title: 'MikuFocus',
      artist: '准备开始',
    ));
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      controls: const [],
      processingState: AudioProcessingState.idle,
    ));
  }

  /// 上次通知发出的运行态；playbackState 仅在 running 变化时重发。
  bool? _lastNotifiedRunning;

  /// 更新通知的阶段与剩余时间显示（US-F02/US-F03）。
  ///
  /// 由 FocusController 按秒节流调用；通知按钮随运行态切换：
  /// 「结束」（stop）常驻，中间键按 running 显示 暂停/继续，
  /// 「跳过」（next）仅在计时运行中提供。
  ///
  /// 闪烁优化（真机反馈 R1）：mediaItem 与 playbackState 各触发一次系统
  /// notify()，双发会让通知每秒重绘两次（M500 上肉眼可见闪烁）。
  /// playbackState 只在 running 变化时才重发（按钮内容仅随运行态变），
  /// 每秒只剩 mediaItem 一次刷新。
  void updateTimerDisplay({
    required String phaseLabel,
    required String timeText,
    required bool running,
  }) {
    mediaItem.add(MediaItem(
      id: 'ai_clock_focus',
      title: 'MikuFocus',
      artist: '$phaseLabel · $timeText',
    ));
    if (running == _lastNotifiedRunning) return;
    _lastNotifiedRunning = running;
    playbackState.add(playbackState.value.copyWith(
      playing: running,
      controls: [
        MediaControl.stop,
        if (running) MediaControl.pause else MediaControl.play,
        if (running) MediaControl.skipToNext,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
    ));
  }

  // ------------------------------------------------------------ 语义回调

  /// M500 的播放/暂停键（KEYCODE_MEDIA_PLAY_PAUSE, 85）。
  /// 本 App 霸占期间不真正播放音频，play/pause 均视为击键。
  ///
  /// 延迟取舍：当前映射绑定了双/三按时（默认映射双按=音乐下一首），
  /// 单按经 300ms 多击窗口结算（平台标准双击间隔，区分单/双按的必要
  /// 代价）；用户在映射编辑器解绑全部多击手势后，单按立即下发（<100ms）。
  @override
  Future<void> play() async => _onPlayPauseKey();

  @override
  Future<void> pause() async => _onPlayPauseKey();

  void _onPlayPauseKey() {
    if (!_shouldHandleKeys) return; // 按键属于系统音乐 App
    if (_commandBus.keyMap.bindsMultiTap) {
      _grouper.tap();
    } else {
      _commandBus.dispatchKey(MediaKeyEvent.singleTap);
    }
  }

  /// 防回环守卫（双按转发「音乐下一首」用）：本时刻之前收到的
  /// skipToNext 一律忽略。转发路径 releaseKeys → 原生 dispatch ——若
  /// ROM 把转发的 NEXT 又路由回本 App 的 MediaSession（我们仍是顶层
  /// 会话时会发生），守卫把回环事件吞掉，防止误触发 skipPhase。
  int ignoreNextUntilMillis = 0;

  /// 下一曲键（KEYCODE_MEDIA_NEXT, 87）：直连场景立即下发，无需多击窗口。
  @override
  Future<void> skipToNext() async {
    if (DateTime.now().millisecondsSinceEpoch < ignoreNextUntilMillis) return;
    if (!_shouldHandleKeys) return;
    _commandBus.dispatchKey(MediaKeyEvent.next);
  }

  /// 上一曲键（KEYCODE_MEDIA_PREVIOUS, 88）。
  @override
  Future<void> skipToPrevious() async {
    if (!_shouldHandleKeys) return;
    _commandBus.dispatchKey(MediaKeyEvent.previous);
  }

  /// 通知栏「结束」按钮（US-F02）：与「长按播放键」同语义——结束并保存。
  /// 不调用 super.stop()：服务需保活待命，真正停止由 releaseKeys 管理。
  @override
  Future<void> stop() async {
    if (!_shouldHandleKeys) return;
    _commandBus.dispatchKey(MediaKeyEvent.longPress);
  }

  /// 长按上报入口。
  ///
  /// audio_service 只透传语义回调，不透传 key down/up 原始事件，无法
  /// 在 Dart 侧自行判定长按。
  /// TODO(V0.2): 增加 MethodChannel，在原生侧监听 KeyEvent 的
  /// ACTION_DOWN/ACTION_UP 时长（或在 MediaSession.Callback 中重写
  /// onMediaButtonEvent），判出长按后调用本方法。
  void reportLongPress() {
    if (!_shouldHandleKeys) return;
    _commandBus.dispatchKey(MediaKeyEvent.longPress);
  }

  @override
  Future<void> onTaskRemoved() async {
    // 用户从最近任务划掉 App：释放按键，避免音乐 App 永久失键
    await releaseKeys();
    await super.onTaskRemoved();
  }

  Future<void> dispose() async {
    await releaseKeys();
    await _player.dispose();
  }
}
