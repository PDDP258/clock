/// 读取其它 App 正在播放的音乐（竖屏歌词区数据源，2026-10-05）。
///
/// 经既有 `aiclock/media_forward` 通道的 `getNowPlaying` 方法（MainActivity
/// 硬路径同款资格：通知监听权限 → MediaSessionManager.getActiveSessions），
/// 拿到外部媒体会话的 歌名/歌手/专辑/播放状态/播放位置。不需要任何音乐
/// App 配合；未授权通知读取 / 无外部会话 / 非 Android 环境一律回退 null。
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前播放信息快照。
class NowPlaying {
  const NowPlaying({
    required this.title,
    required this.artist,
    required this.album,
    required this.playing,
    required this.positionMs,
  });

  /// 歌名（可能为空串）
  final String title;

  /// 歌手（可能为空串）
  final String artist;

  /// 专辑（可能为空串）
  final String album;

  /// 是否正在播放
  final bool playing;

  /// 当前播放位置（毫秒，随轮询推进）
  final int positionMs;

  /// 稳定 key：歌词文件按它匹配。
  String get songKey => '$title|$artist';
}

/// 与原生 MainActivity 约定的通道（看板 #38 既有）。
const MethodChannel _channel = MethodChannel('aiclock/media_forward');

/// 单次拉取当前播放信息；任何失败（未授权/无会话/ROM 差异）返回 null。
Future<NowPlaying?> fetchNowPlaying() async {
  try {
    final raw = await _channel.invokeMapMethod<String, dynamic>('getNowPlaying');
    if (raw == null) return null;
    final title = (raw['title'] as String?) ?? '';
    final artist = (raw['artist'] as String?) ?? '';
    // 歌名歌手全空视为无效会话（如占位会话），不展示
    if (title.isEmpty && artist.isEmpty) return null;
    return NowPlaying(
      title: title,
      artist: artist,
      album: (raw['album'] as String?) ?? '',
      playing: (raw['playing'] as bool?) ?? false,
      positionMs: (raw['positionMs'] as num?)?.toInt() ?? 0,
    );
  } on MissingPluginException {
    return null; // 测试/非 Android 环境
  } on Object {
    return null;
  }
}

/// 播放信息轮询器：引用计数（acquire/release），首个消费者启动
/// 2s 周期轮询，最后一个释放即停——只在竖屏歌词区可见时工作。
final nowPlayingProvider =
    StateNotifierProvider<NowPlayingNotifier, NowPlaying?>(
        (ref) => NowPlayingNotifier());

/// 播放信息轮询的读写（state 为最新快照，null = 无外部播放）。
class NowPlayingNotifier extends StateNotifier<NowPlaying?> {
  NowPlayingNotifier() : super(null);

  Timer? _timer;
  int _clients = 0;

  /// 增加一个消费者（页面 initState 时调用）。
  void acquire() {
    if (++_clients == 1) _start();
  }

  /// 减少一个消费者（页面 dispose 时调用）。
  void release() {
    if (--_clients <= 0) {
      _clients = 0;
      _timer?.cancel();
      _timer = null;
      state = null;
    }
  }

  void _start() {
    unawaited(_tick());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  Future<void> _tick() async {
    state = await fetchNowPlaying();
  }
}
