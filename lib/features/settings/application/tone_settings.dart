/// 自定义提示音的配置存取（application 层）。
///
/// 持久化：SharedPreferences 单键 `custom_tones_v1`（JSON，键 = 槽位键）。
/// 槽位目录与钳制规则见 `core/feedback/custom_tone.dart`（纯 Dart，可单测）。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/feedback/custom_tone.dart';
import '../../../platform/audio/audio_tools_channel.dart';
import '../../../platform/prefs/prefs_provider.dart';

/// 自定义提示音通道（测试覆盖为 fake）。
final audioToolsChannelProvider =
    Provider<AudioToolsChannel>((ref) => const AudioToolsChannel());

/// 各槽位的自定义配置（键 = 槽位键，见 [kToneSlots]）。
final customTonesProvider = StateNotifierProvider<CustomTonesNotifier,
    Map<String, ToneCustom>>((ref) => CustomTonesNotifier(
          ref.watch(sharedPreferencesProvider),
        ));

class CustomTonesNotifier
    extends StateNotifier<Map<String, ToneCustom>> {
  CustomTonesNotifier(this._prefs) : super(_load(_prefs));

  static const _kKey = 'custom_tones_v1';
  final SharedPreferences _prefs;

  static Map<String, ToneCustom> _load(SharedPreferences prefs) =>
      toneMapDecode(prefs.getString(_kKey));

  Future<void> _persist() async =>
      _prefs.setString(_kKey, toneMapEncode(state));

  /// 绑定/更新一个槽位（长度与起点先钳制到合法区间）。
  Future<void> set(String slotKey, ToneCustom tone) async {
    final duration = toneClampDuration(tone.durationMs);
    final start = toneClampStart(tone.startMs, duration, tone.trackMs);
    state = {
      ...state,
      slotKey: tone.copyWith(startMs: start, durationMs: duration),
    };
    await _persist();
  }

  /// 解绑（回退内置音型；音频文件保留在 tones/ 下，可再次绑定）。
  Future<void> clear(String slotKey) async {
    state = Map<String, ToneCustom>.from(state)..remove(slotKey);
    await _persist();
  }
}

/// 把通道返回的选音结果转成槽位配置（纯函数，可单测）。
///
/// 片段默认从 0 开始、长度 = min(总时长, 5s)——用户在编辑器里再调。
ToneCustom toneCustomFromPick(PickedAudio pick) {
  final duration = toneClampDuration(pick.durationMs);
  return ToneCustom(
    path: pick.path,
    name: pick.name,
    startMs: 0,
    durationMs: duration,
    trackMs: pick.durationMs,
  );
}
