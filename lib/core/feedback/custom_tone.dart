/// 自定义提示音的数据模型与规则（纯 Dart，可独立单测）。
///
/// 口径（2026-10-05 用户定稿）：
/// - 每个提示音槽位可绑定一段**用户音频文件的片段**；不绑定则用内置音型；
/// - 片段长度 **最长 5000ms**（内置音型约 1s，自定义给到 5s 余量）；
/// - 片段起点用「音乐进度轴上的可拖动音符」标记（见编辑浮窗），
///   模型层只存毫秒数；
/// - 片段不允许越过音频末尾：`startMs + durationMs ≤ trackMs`，
///   越界时**钳制起点**（保持用户选的长度，挪动音符）而不是截断长度。
library;

import 'dart:convert';

/// 单个提示音槽位的自定义配置。
class ToneCustom {
  const ToneCustom({
    required this.path,
    required this.name,
    required this.startMs,
    required this.durationMs,
    required this.trackMs,
  });

  /// 音频文件落盘绝对路径（应用专属外存 `tones/` 内）
  final String path;

  /// 原文件名（展示用）
  final String name;

  /// 提示音片段在源音频里的起点（毫秒）
  final int startMs;

  /// 提示音片段长度（毫秒，[kToneMinMs, kToneMaxMs]）
  final int durationMs;

  /// 源音频总时长（毫秒）；编辑器重开时定位音符/波形用
  final int trackMs;

  ToneCustom copyWith({int? startMs, int? durationMs}) => ToneCustom(
        path: path,
        name: name,
        startMs: startMs ?? this.startMs,
        durationMs: durationMs ?? this.durationMs,
        trackMs: trackMs,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'name': name,
        'startMs': startMs,
        'durationMs': durationMs,
        'trackMs': trackMs,
      };

  static ToneCustom? fromJson(Map<Object?, Object?> json) {
    final path = json['path'];
    if (path is! String || path.isEmpty) return null;
    return ToneCustom(
      path: path,
      name: json['name'] is String ? json['name'] as String : '',
      startMs: _intOf(json['startMs']),
      durationMs: _intOf(json['durationMs']),
      trackMs: _intOf(json['trackMs']),
    );
  }

  static int _intOf(Object? raw) =>
      raw is int ? raw : (raw is num ? raw.toInt() : 0);
}

/// 片段长度的下限（毫秒）：再短就没有辨识度了。
const int kToneMinMs = 100;

/// 片段长度的上限（毫秒）：用户口径 5 秒。
const int kToneMaxMs = 5000;

/// 钳制片段长度到合法区间。
int toneClampDuration(int ms) => ms.clamp(kToneMinMs, kToneMaxMs);

/// 钳制片段起点：不小于 0，且 `start + duration ≤ track`（音频末尾内）。
///
/// 音频比片段还短（或探测失败 trackMs=0）时起点只能为 0。
int toneClampStart(int startMs, int durationMs, int trackMs) {
  if (trackMs <= 0) return 0;
  final maxStart = trackMs - durationMs;
  if (maxStart <= 0) return 0;
  return startMs.clamp(0, maxStart);
}

/// 提示音槽位目录：槽位键（= 内置音型资产路径）→ 中文名。
///
/// start/resume 共用同一资产，所以也是同一个自定义槽位——
/// 「开始」和「继续」本来就是同一种语义（上行动感）。
const Map<String, String> kToneSlots = <String, String>{
  'assets/audio/tone_start.wav': '开始 / 继续',
  'assets/audio/tone_pause.wav': '暂停',
  'assets/audio/tone_end.wav': '结束',
  'assets/audio/tone_skip.wav': '跳过 / 下一首',
  'assets/audio/tone_mark.wav': '打点 / +5分钟',
  'assets/audio/tone_phase.wav': '阶段提醒',
  'assets/audio/tone_celebrate.wav': '四轮庆祝',
};

/// 自定义配置的持久化编解码（SharedPreferences 里的一个 JSON 串）。
///
/// 键 = 槽位键（音型资产路径）；单条损坏只丢那一条（坏行不拖垮整份）。
Map<String, ToneCustom> toneMapDecode(String? raw) {
  if (raw == null || raw.isEmpty) return const <String, ToneCustom>{};
  Object? root;
  try {
    root = jsonDecode(raw);
  } on FormatException {
    return const <String, ToneCustom>{};
  }
  if (root is! Map) return const <String, ToneCustom>{};
  return <String, ToneCustom>{
    for (final entry in root.entries)
      if (entry.value is Map)
        if (ToneCustom.fromJson(entry.value as Map<Object?, Object?>)
            case final tone?)
          entry.key: tone,
  };
}

String toneMapEncode(Map<String, ToneCustom> tones) =>
    jsonEncode(<String, Object?>{
      for (final e in tones.entries) e.key: e.value.toJson(),
    });
