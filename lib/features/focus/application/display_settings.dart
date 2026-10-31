/// 竖屏「余光」布局相关的显示开关（2026-10-05）：
/// 竖排布局开关与时钟数字体系，均为 shared_preferences 持久化的简单配置，
/// 读写模式与 [GlowIntensityNotifier] 一致（缺失回退默认值）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/timer/numeral.dart';
import '../../../platform/prefs/prefs_provider.dart';

/// 竖屏「余光」布局开关：开启后允许竖屏姿态，专注页竖屏分支使用
/// 竖排布局（竖排辉光管时钟 / 歌词列 / 双进度条）；关闭则恢复
/// 锁定横屏（sensorLandscape），与 M500 历史行为一致。默认关闭。
final portraitLayoutEnabledProvider =
    StateNotifierProvider<PortraitLayoutNotifier, bool>(
        (ref) => PortraitLayoutNotifier(ref.watch(sharedPreferencesProvider)));

/// 竖排布局开关的读写与持久化。
class PortraitLayoutNotifier extends StateNotifier<bool> {
  PortraitLayoutNotifier(this._prefs)
      : super(_prefs.getBool(_kKey) ?? false);

  static const _kKey = 'portrait_layout_enabled';
  final SharedPreferences _prefs;

  Future<void> setEnabled(bool value) async {
    state = value;
    await _prefs.setBool(_kKey, value);
  }
}

/// 时钟数字体系（[ClockNumeral]）。横屏恒为阿拉伯数字，仅竖屏布局读取。
final clockNumeralProvider =
    StateNotifierProvider<ClockNumeralNotifier, ClockNumeral>(
        (ref) => ClockNumeralNotifier(ref.watch(sharedPreferencesProvider)));

/// 数字体系的读写与持久化（存 enum name，缺失/非法回退阿拉伯）。
class ClockNumeralNotifier extends StateNotifier<ClockNumeral> {
  ClockNumeralNotifier(this._prefs)
      : super(_read(_prefs.getString(_kKey)));

  static const _kKey = 'clock_numeral';
  final SharedPreferences _prefs;

  static ClockNumeral _read(String? raw) => ClockNumeral.values.asNameMap()[raw] ??
      ClockNumeral.arabic;

  Future<void> set(ClockNumeral value) async {
    state = value;
    await _prefs.setString(_kKey, value.name);
  }
}
