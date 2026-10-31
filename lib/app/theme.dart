/// 应用主题：初音未来联名三方案 × 深/浅两套 + ThemeExtension 皮肤扩展点。
///
/// M500 为初音联名设备（5 英寸 720p 小屏，整体高对比、大字号、少装饰）。
/// 配色按 design token 三层组织：
///   primitive（各方案 hex 常量）→ semantic（[AppSkin] 四语义色）
///   → component（计时环/图例/按钮等用色点）。
/// 三套方案取自初音 IP 官方「季节系列」形态，区分度与特色天然成立：
///   经典葱色（#39C5BB 官方苍绿）/ 樱未来（粉白春樱）/ 雪未来（冰雪蓝白）。
library;

import 'package:flutter/material.dart';

/// 主题方案（初音联名三形态）。
enum AppThemeScheme {
  /// 经典葱色：初音本体苍绿 #39C5BB，冷色科技感（默认，与机身联名一致）
  classicMiku('classic_miku', '经典葱色'),

  /// 樱未来：粉白春樱，暖调柔和
  sakuraMiku('sakura_miku', '樱未来'),

  /// 雪未来：冰雪蓝白，清冷低饱和，夜间最不刺眼
  snowMiku('snow_miku', '雪未来');

  const AppThemeScheme(this.storageKey, this.label);

  /// 持久化键值
  final String storageKey;

  /// 设置页显示名
  final String label;

  /// 从持久化键值恢复；非法/缺失值回退 [classicMiku]。
  static AppThemeScheme fromStorageKey(String? key) {
    for (final scheme in values) {
      if (scheme.storageKey == key) return scheme;
    }
    return AppThemeScheme.classicMiku;
  }
}

/// 皮肤扩展点（semantic 层）：专注/休息环色 + 强调色 + 危险色。
/// 后续换肤（V0.4 游戏化皮肤）只需新增方案并挂到 ThemeData.extensions。
@immutable
class AppSkin extends ThemeExtension<AppSkin> {
  const AppSkin({
    required this.focusRingColor,
    required this.breakRingColor,
    required this.accentColor,
    required this.dangerColor,
  });

  /// 专注阶段计时环颜色
  final Color focusRingColor;

  /// 休息阶段计时环颜色
  final Color breakRingColor;

  /// 强调色：正计时区分色、页面主强调（同时作 ColorScheme 种子）
  final Color accentColor;

  /// 结束/危险操作颜色（跨方案稳定红系，避免认知漂移）
  final Color dangerColor;

  @override
  AppSkin copyWith({
    Color? focusRingColor,
    Color? breakRingColor,
    Color? accentColor,
    Color? dangerColor,
  }) {
    return AppSkin(
      focusRingColor: focusRingColor ?? this.focusRingColor,
      breakRingColor: breakRingColor ?? this.breakRingColor,
      accentColor: accentColor ?? this.accentColor,
      dangerColor: dangerColor ?? this.dangerColor,
    );
  }

  @override
  AppSkin lerp(ThemeExtension<AppSkin>? other, double t) {
    if (other is! AppSkin) return this;
    return AppSkin(
      focusRingColor: Color.lerp(focusRingColor, other.focusRingColor, t)!,
      breakRingColor: Color.lerp(breakRingColor, other.breakRingColor, t)!,
      accentColor: Color.lerp(accentColor, other.accentColor, t)!,
      dangerColor: Color.lerp(dangerColor, other.dangerColor, t)!,
    );
  }
}

/// 各方案的 primitive 色值与皮肤映射。
extension AppThemeSchemeSkin on AppThemeScheme {
  /// 方案皮肤（semantic 层）
  AppSkin get skin => switch (this) {
        AppThemeScheme.classicMiku => const AppSkin(
            focusRingColor: Color(0xFF39C5BB), // 苍绿（官方代表色）
            breakRingColor: Color(0xFFE53935), // 红（P0 定稿：经典无橘黄，
            // 休息红主；调色板=蓝绿/红/紫/黑/白）
            accentColor: Color(0xFF39C5BB),
            dangerColor: Color(0xFFE53935),
          ),
        AppThemeScheme.sakuraMiku => const AppSkin(
            focusRingColor: Color(0xFFF06292), // 樱粉
            breakRingColor: Color(0xFF81C784), // 新叶绿
            accentColor: Color(0xFFF06292),
            dangerColor: Color(0xFFD32F2F),
          ),
        AppThemeScheme.snowMiku => const AppSkin(
            focusRingColor: Color(0xFF4FC3F7), // 冰蓝
            breakRingColor: Color(0xFFB39DDB), // 薰衣草紫
            accentColor: Color(0xFF4FC3F7),
            dangerColor: Color(0xFFEF5350),
          ),
      };

  /// ColorScheme 种子色（= 强调色）
  Color get seedColor => skin.accentColor;
}

/// 主题工厂。
abstract final class AppTheme {
  /// 浅色主题
  static ThemeData light(AppThemeScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: scheme.seedColor),
      extensions: <ThemeExtension<dynamic>>[scheme.skin],
    );
  }

  /// 深色主题（专注场景主推，OLED 省电）
  static ThemeData dark(AppThemeScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: scheme.seedColor,
        brightness: Brightness.dark,
        // 纯色背景减蓝：fromSeed 的深色调 surface 自带一层蓝味，
        // 用户 2026-10-06 口径要「黑带点蓝的纯色背景，减少蓝色」——
        // 用中性深灰黑覆盖。
        surface: const Color(0xFF141414),
      ),
      extensions: <ThemeExtension<dynamic>>[scheme.skin],
    );
  }
}

/// 便捷取值：`context.skin`
extension AppSkinContext on BuildContext {
  /// 当前皮肤扩展
  AppSkin get skin =>
      Theme.of(this).extension<AppSkin>() ?? AppThemeScheme.classicMiku.skin;
}
