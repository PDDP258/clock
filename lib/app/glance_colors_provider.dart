/// 余光页显示配色自定义（P0，2026-08-01 用户定稿；2026-10-03 扩展）。
///
/// 四个元素各自可选色：专注时钟 / 专注进度条 / 休息时钟 / 休息进度条。
/// 调色板 13 色——原 5 色（蓝绿/红/紫/白/黑）+ 2026-10-03 从背景图库
/// 高频主色提取的 8 色（亮青/深海蓝/天蓝/樱粉/玫红/珊瑚/橄榄/浅青）。
/// **新色一律追加在尾部**：旧存储存的是下标，移动既有项会让老用户换色。
///
/// 2026-10-03 用户需求（看板 #58）：
/// - 元素存**ARGB 整数**而不是调色板下标——支持「自定义」任意颜色（HSV 拾色器）；
/// - 配色**按主题方案独立存储**（经典葱色/樱未来/雪未来三套互不覆盖，
///   键名 `glance2_<schemeKey>_<element>`）；切方案即切到该方案自己的配色。
/// - 兼容迁移：新键缺失时读旧全局键 `glance_focus_clock` 等（下标→颜色），
///   归入经典葱色方案；再缺省用本方案默认。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/prefs/prefs_provider.dart';
import 'theme.dart';
import 'theme_provider.dart';

/// 余光页调色板（预设色，顺序即设置页展示顺序；下标仅作旧存储迁移用）。
const kGlancePalette = <Color>[
  Color(0xFF39C5BB), // 0 蓝绿（初音苍绿）
  Color(0xFFE53935), // 1 红
  Color(0xFFB39DDB), // 2 紫
  Color(0xFFFAFAFA), // 3 白
  Color(0xFF111111), // 4 黑
  // ---- 2026-10-03 追加：从背景图库高频主色提取（tool/extract 人工挑选）----
  Color(0xFF32E7F0), // 5 亮青（霓虹青，图库高频）
  Color(0xFF0D76A7), // 6 深海蓝
  Color(0xFF49A6E2), // 7 天蓝
  Color(0xFFE8A2C0), // 8 樱粉（图库高频粉）
  Color(0xFFAE4B6B), // 9 玫红
  Color(0xFFDA856D), // 10 珊瑚
  Color(0xFFC1BC8C), // 11 橄榄
  Color(0xFFB2E5E0), // 12 浅青
];

/// 调色板各色显示名（与 [kGlancePalette] 同序）。
const kGlancePaletteNames = <String>[
  '蓝绿', '红', '紫', '白', '黑',
  '亮青', '深海蓝', '天蓝', '樱粉', '玫红', '珊瑚', '橄榄', '浅青',
];

/// 四元素配色（每元素一个 ARGB 颜色值）。
@immutable
class GlanceColors {
  const GlanceColors({
    required this.focusClock,
    required this.focusBar,
    required this.breakClock,
    required this.breakBar,
  });

  /// 默认（P0 用户定稿）：专注=蓝绿时钟+红条，休息=红时钟+蓝绿条（红主蓝辅）
  static const defaults = GlanceColors(
    focusClock: 0xFF39C5BB,
    focusBar: 0xFFE53935,
    breakClock: 0xFFE53935,
    breakBar: 0xFF39C5BB,
  );

  /// 专注时钟颜色（ARGB）
  final int focusClock;

  /// 专注进度条颜色（ARGB）
  final int focusBar;

  /// 休息时钟颜色（ARGB）
  final int breakClock;

  /// 休息进度条颜色（ARGB）
  final int breakBar;

  /// 专注时钟色
  Color get focusClockColor => Color(focusClock);

  /// 专注进度条色
  Color get focusBarColor => Color(focusBar);

  /// 休息时钟色
  Color get breakClockColor => Color(breakClock);

  /// 休息进度条色
  Color get breakBarColor => Color(breakBar);

  GlanceColors copyWith({
    int? focusClock,
    int? focusBar,
    int? breakClock,
    int? breakBar,
  }) {
    return GlanceColors(
      focusClock: focusClock ?? this.focusClock,
      focusBar: focusBar ?? this.focusBar,
      breakClock: breakClock ?? this.breakClock,
      breakBar: breakBar ?? this.breakBar,
    );
  }
}

/// 显示配色 Provider：**按当前主题方案独立读取/存储**（看板 #58）。
///
/// watch [appThemeSchemeProvider]——切方案时 provider 重建，
/// 自动读到该方案自己的一套配色；四个元素互不影响。
final glanceColorsProvider =
    StateNotifierProvider<GlanceColorsNotifier, GlanceColors>((ref) {
  final scheme = ref.watch(appThemeSchemeProvider);
  return GlanceColorsNotifier(ref.watch(sharedPreferencesProvider), scheme);
});

/// 四元素配色的读写与持久化（ARGB int；键按方案命名空间隔离）。
class GlanceColorsNotifier extends StateNotifier<GlanceColors> {
  GlanceColorsNotifier(this._prefs, this._scheme)
      : super(GlanceColors(
          focusClock: _read(_prefs, _scheme, _Element.focusClock),
          focusBar: _read(_prefs, _scheme, _Element.focusBar),
          breakClock: _read(_prefs, _scheme, _Element.breakClock),
          breakBar: _read(_prefs, _scheme, _Element.breakBar),
        ));

  final SharedPreferences _prefs;
  final AppThemeScheme _scheme;

  /// 旧版全局键（下标存储）——迁移源，只归属经典葱色方案。
  static const _legacyKeys = <_Element, String>{
    _Element.focusClock: 'glance_focus_clock',
    _Element.focusBar: 'glance_focus_bar',
    _Element.breakClock: 'glance_break_clock',
    _Element.breakBar: 'glance_break_bar',
  };

  static String _keyOf(AppThemeScheme scheme, _Element e) =>
      'glance2_${scheme.storageKey}_${e.name}';

  /// 迁移用的旧下标 → 颜色（越界回退 null 走默认）。
  static int? _legacyColorOf(Object? raw) {
    if (raw is! int) return null;
    if (raw < 0 || raw >= kGlancePalette.length) return null;
    return kGlancePalette[raw].toARGB32();
  }

  static int _read(
    SharedPreferences prefs,
    AppThemeScheme scheme,
    _Element element,
  ) {
    // 1) 新键（ARGB，按方案隔离）
    final v = prefs.getInt(_keyOf(scheme, element));
    if (v != null) return v;
    // 2) 迁移：旧全局键（下标）只在经典方案生效——旧存储本就是全局一份
    if (scheme == AppThemeScheme.classicMiku) {
      final legacy = _legacyColorOf(prefs.getInt(_legacyKeys[element]!));
      if (legacy != null) return legacy;
    }
    // 3) 默认
    return switch (element) {
      _Element.focusClock => GlanceColors.defaults.focusClock,
      _Element.focusBar => GlanceColors.defaults.focusBar,
      _Element.breakClock => GlanceColors.defaults.breakClock,
      _Element.breakBar => GlanceColors.defaults.breakBar,
    };
  }

  /// 更新单个元素（ARGB 值，写入当前方案的命名空间）。
  Future<void> update({
    int? focusClock,
    int? focusBar,
    int? breakClock,
    int? breakBar,
  }) async {
    state = state.copyWith(
      focusClock: focusClock,
      focusBar: focusBar,
      breakClock: breakClock,
      breakBar: breakBar,
    );
    if (focusClock != null) {
      await _prefs.setInt(_keyOf(_scheme, _Element.focusClock), focusClock);
    }
    if (focusBar != null) {
      await _prefs.setInt(_keyOf(_scheme, _Element.focusBar), focusBar);
    }
    if (breakClock != null) {
      await _prefs.setInt(_keyOf(_scheme, _Element.breakClock), breakClock);
    }
    if (breakBar != null) {
      await _prefs.setInt(_keyOf(_scheme, _Element.breakBar), breakBar);
    }
  }
}

/// 四个可配元素（键名片段，`name` 进存储键）。
enum _Element { focusClock, focusBar, breakClock, breakBar }

/// 时钟辉光亮度（百分比 0-150，0 = 关闭；看板 #37 用户可调，
/// 上限 150% 为 PD 2026-10-06 扩大的过量辉光档）。
final glowIntensityProvider =
    StateNotifierProvider<GlowIntensityNotifier, int>(
        (ref) => GlowIntensityNotifier(ref.watch(sharedPreferencesProvider)));

/// 辉光亮度的读写与持久化（缺失/非法回退 80）。
class GlowIntensityNotifier extends StateNotifier<int> {
  GlowIntensityNotifier(this._prefs)
      : super((_prefs.getInt(_kKey) ?? 80).clamp(0, 150));

  static const _kKey = 'glance_glow_intensity';
  final SharedPreferences _prefs;

  Future<void> set(int percent) async {
    final v = percent.clamp(0, 150);
    state = v;
    await _prefs.setInt(_kKey, v);
  }
}
