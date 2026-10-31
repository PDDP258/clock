/// 声音反馈平台服务：预加载提示音，保证端到端延迟 <100ms。
///
/// 低延迟要点：
/// - 每个音型一个独立的 AudioPlayer，init 时完成 setAsset 加载；
///   播放时仅 seek(0)+play，避免首次加载 IO 阻塞（这是 <100ms 的关键）。
/// - play 不 await 播放完成（确认音是「发令枪」，发出去即可）。
///
/// 音频焦点联调（ADR-0001 后果）：确认音短促，不调用 AudioSession.setActive，
/// 即不请求音频焦点，避免打断用户听歌；如真机出现与音乐互相压音，
/// 再评估 transient 焦点策略（见技术架构设计 §5.5）。
/// 2026-10-01 用户口径：震动通道整体移除。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/feedback/custom_tone.dart';
import '../../core/feedback/key_feedback.dart';
import '../prefs/prefs_provider.dart';

/// 声音反馈服务（main.dart 中创建并 init 后 override 注入）。
final keyFeedbackServiceProvider = Provider<KeyFeedbackService>(
  (ref) => throw UnimplementedError('需在 main.dart 的 ProviderScope 中 override'),
);

/// 反馈设置（持久化到 SharedPreferences）。
final keyFeedbackSettingsProvider =
    StateNotifierProvider<KeyFeedbackSettingsNotifier, KeyFeedbackSettings>(
  (ref) =>
      KeyFeedbackSettingsNotifier(ref.watch(sharedPreferencesProvider)),
);

/// 设置的读写与持久化。
class KeyFeedbackSettingsNotifier extends StateNotifier<KeyFeedbackSettings> {
  KeyFeedbackSettingsNotifier(this._prefs) : super(_load(_prefs));

  static const _kSettings = 'key_feedback_settings';
  final SharedPreferences _prefs;

  static KeyFeedbackSettings _load(SharedPreferences prefs) {
    final raw = prefs.getString(_kSettings);
    if (raw == null) return KeyFeedbackSettings.defaults;
    try {
      return KeyFeedbackSettings.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } on FormatException {
      return KeyFeedbackSettings.defaults;
    }
  }

  Future<void> update(KeyFeedbackSettings settings) async {
    state = settings;
    await _prefs.setString(_kSettings, jsonEncode(settings.toJson()));
  }
}

/// 声音反馈执行器。
class KeyFeedbackService {
  KeyFeedbackService();

  /// 音型资产 → 预加载播放器
  final Map<String, AudioPlayer> _players = {};

  bool _initialized = false;

  /// 预加载全部音型。App 启动时调用一次。
  Future<void> init() async {
    if (_initialized) return;
    for (final event in FeedbackEvent.values) {
      final asset = FeedbackPolicy.toneAssetFor(event);
      if (_players.containsKey(asset)) continue; // start/resume 共用资产
      final player = AudioPlayer();
      await player.setAsset(asset);
      // 确认音音量压低，避免盖过/惊扰正在听的音乐（§5.5 联调基线）
      await player.setVolume(0.7);
      _players[asset] = player;
    }
    _initialized = true;
  }

  /// 执行一次反馈。同步返回——播放都在后台发出，不阻塞按键链路。
  ///
  /// [custom] 非空且文件存在时播放用户自定义片段（起点+长度，
  /// 见 `custom_tone.dart` 的钳制规则），否则回退内置音型。
  void play(
    FeedbackEvent event,
    KeyFeedbackSettings settings, {
    ToneCustom? custom,
  }) {
    if (!_initialized) return;
    final plan = FeedbackPolicy.decide(settings, event);
    final asset = plan.toneAsset;
    if (asset == null) return;

    // 自定义片段：单实例播放器按需换源，seek 到起点、播够时长即停。
    if (custom != null && File(custom.path).existsSync()) {
      unawaited(_playClip(custom));
      return;
    }

    final player = _players[asset];
    if (player != null) {
      unawaited(() async {
        await player.seek(Duration.zero);
        await player.play();
      }());
    }
  }

  /// 播放用户自定义片段。换源只在路径变化时发生（同一音频反复触发
  /// 不重读文件）；播够 durationMs 即 pause——确认音是「发令枪」，
  /// 到点就停，不等自然结束（自定义可以长到 5s）。
  Future<void> _playClip(ToneCustom tone) async {
    final player = _clipPlayer ??= AudioPlayer();
    await player.setVolume(0.7);
    if (_clipPath != tone.path) {
      await player.setFilePath(tone.path);
      _clipPath = tone.path;
    }
    _clipStopTimer?.cancel();
    await player.seek(Duration(milliseconds: tone.startMs));
    await player.play();
    _clipStopTimer = Timer(
      Duration(milliseconds: tone.durationMs),
      () => unawaited(player.pause()),
    );
  }

  AudioPlayer? _clipPlayer;
  String? _clipPath;
  Timer? _clipStopTimer;

  Future<void> dispose() async {
    _clipStopTimer?.cancel();
    await _clipPlayer?.dispose();
    _clipPlayer = null;
    _clipPath = null;
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
  }
}
