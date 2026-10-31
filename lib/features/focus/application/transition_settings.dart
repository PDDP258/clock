/// 轮次转场动画的强度档位（2026-10-06，看板 #62）。
///
/// 转场是**余光场景**的编排：阶段一变，染色、阶段字标、巨钟、轮次豆
/// 若各自同时乱动，一米外只读出「屏幕抖了一下」；排成三段式时间轴
/// （退场 → 换场 → 落定）才读得出「换段了」。这套编排由
/// `presentation/round_transition.dart` 实现，本文件只管**档位与持久化**。
///
/// 三档：
/// - [full]：完整编排（位移 + 换字 + 颜色交叉 + 豆子依次点亮）；
/// - [lite]：精简——只留「染色渐变」与「豆子点亮」这两个最省的事件，
///   跳过所有位移/换字（省电与「动一下就够」的场景）；
/// - [off]：全部瞬切（与转场功能上线前的历史行为一致）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../platform/prefs/prefs_provider.dart';

/// 转场强度档。
enum TransitionIntensity {
  /// 完整编排（默认）。
  full('完整', '染色横扫 + 阶段字换位 + 时钟回滚换色 + 轮次豆依次点亮'),

  /// 精简：只保留染色与豆子。
  lite('精简', '只保留阶段染色与轮次豆点亮，无位移换字'),

  /// 关闭：瞬切。
  off('关闭', '阶段变化立即切换，不做任何过渡动画');

  const TransitionIntensity(this.label, this.hint);

  /// 档位名（设置页显示）。
  final String label;

  /// 一句话说明（设置页副标题）。
  final String hint;

  /// 档位 name（持久化用）。
  String get wire => name;
}

/// 档位名解析（**纯函数，可单测**）：未知/缺失一律回退 [full]，
/// 老用户升级后不会被一个坏键值卡在「关闭」上。
TransitionIntensity transitionIntensityFromName(String? raw) =>
    TransitionIntensity.values.asNameMap()[raw] ?? TransitionIntensity.full;

/// 当前转场强度（SharedPreferences 持久化，缺失回退完整）。
final transitionIntensityProvider =
    StateNotifierProvider<TransitionIntensityNotifier, TransitionIntensity>(
        (ref) => TransitionIntensityNotifier(ref.watch(sharedPreferencesProvider)));

/// 转场强度的读写与持久化（存 enum name，与 [ClockNumeralNotifier] 同模式）。
class TransitionIntensityNotifier extends StateNotifier<TransitionIntensity> {
  TransitionIntensityNotifier(this._prefs)
      : super(transitionIntensityFromName(_prefs.getString(_kKey)));

  static const _kKey = 'transition_intensity';
  final SharedPreferences _prefs;

  Future<void> set(TransitionIntensity value) async {
    state = value;
    await _prefs.setString(_kKey, value.wire);
  }
}
