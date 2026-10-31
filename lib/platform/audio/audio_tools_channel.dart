/// 自定义提示音的原生通道（platform 层，`aiclock/audio`）。
///
/// 与 `background_import_channel` 同一口径：原生不可用时（单测/桌面）
/// **静默返回空**——提示音是锦上添花，不该让设置页报错。
library;

import 'package:flutter/services.dart';

/// 通道名（与 AudioToolsPlugin.kt 一致）。
const String kAudioToolsChannelName = 'aiclock/audio';

/// 一次选音频的结果（已拷入应用外存）。
class PickedAudio {
  const PickedAudio({
    required this.path,
    required this.name,
    required this.durationMs,
  });

  /// 落盘绝对路径（`tones/t_<hash8>.<ext>`）
  final String path;

  /// 原文件名（展示用）
  final String name;

  /// 总时长（毫秒；≤0 表示探测失败）
  final int durationMs;

  static PickedAudio? fromMap(Object? raw) {
    if (raw is! Map || raw['ok'] != true) return null;
    final path = raw['path'];
    final duration = raw['durationMs'];
    if (path is! String || path.isEmpty) return null;
    if (duration is! num || duration <= 0) return null;
    return PickedAudio(
      path: path,
      name: raw['name'] is String ? raw['name'] as String : '',
      durationMs: duration.toInt(),
    );
  }
}

/// 原生通道的 Dart 包装。
class AudioToolsChannel {
  const AudioToolsChannel();

  static const MethodChannel _channel = MethodChannel(kAudioToolsChannelName);

  /// 打开系统文件选择器选一条音频（单选）。
  /// 返回 null = 用户取消 / 原生不可用 / 导入失败。
  Future<PickedAudio?> pick() async {
    final raw = await _invoke<Map<Object?, Object?>>('pickAudio', null);
    return PickedAudio.fromMap(raw);
  }

  /// 解码音频提取波形（振幅数组，0..1，长度 = [bars]）。
  /// 失败/原生不可用返回空列表（编辑器退化为纯进度轴）。
  Future<List<double>> extractWaveform(String path, {int bars = 120}) async {
    final raw = await _invoke<List<Object?>>(
      'extractWaveform',
      <String, Object?>{'path': path, 'bars': bars},
    );
    if (raw == null) return const <double>[];
    return <double>[
      for (final v in raw)
        if (v is num && v > 0) v.toDouble() else 0.04,
    ];
  }

  Future<T?> _invoke<T>(String method, Object? args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
