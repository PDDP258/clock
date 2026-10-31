/// 主题方案（初音联名三形态）纯 Dart 用例：持久化往返、回退、区分度护栏。
library;

import 'package:ai_clock/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppThemeScheme 持久化', () {
    test('storageKey 往返完整', () {
      for (final scheme in AppThemeScheme.values) {
        expect(AppThemeScheme.fromStorageKey(scheme.storageKey), scheme);
      }
    });

    test('非法/缺失值回退经典葱色', () {
      expect(AppThemeScheme.fromStorageKey(null), AppThemeScheme.classicMiku);
      expect(
          AppThemeScheme.fromStorageKey('bogus'), AppThemeScheme.classicMiku);
    });

    test('storageKey 两两不同（防持久化串号）', () {
      final keys = AppThemeScheme.values.map((s) => s.storageKey).toSet();
      expect(keys, hasLength(AppThemeScheme.values.length));
    });
  });

  group('三方案区分度护栏（防未来改色撞车）', () {
    test('专注环色两两不同', () {
      final colors =
          AppThemeScheme.values.map((s) => s.skin.focusRingColor).toSet();
      expect(colors, hasLength(AppThemeScheme.values.length));
    });

    test('休息环色两两不同', () {
      final colors =
          AppThemeScheme.values.map((s) => s.skin.breakRingColor).toSet();
      expect(colors, hasLength(AppThemeScheme.values.length));
    });

    test('每方案四色齐全且强调色=种子色', () {
      for (final scheme in AppThemeScheme.values) {
        expect(scheme.seedColor, scheme.skin.accentColor);
      }
    });

    test('经典葱色专注环为初音官方苍绿 #39C5BB', () {
      expect(AppThemeScheme.classicMiku.skin.focusRingColor,
          const Color(0xFF39C5BB));
    });
  });

  group('AppSkin lerp/copyWith', () {
    test('lerp 四色完整过渡', () {
      const a = AppThemeScheme.classicMiku;
      const b = AppThemeScheme.sakuraMiku;
      final mid = a.skin.lerp(b.skin, 0.5);
      expect(mid.focusRingColor,
          Color.lerp(a.skin.focusRingColor, b.skin.focusRingColor, 0.5));
      expect(mid.breakRingColor,
          Color.lerp(a.skin.breakRingColor, b.skin.breakRingColor, 0.5));
      expect(mid.accentColor,
          Color.lerp(a.skin.accentColor, b.skin.accentColor, 0.5));
      expect(mid.dangerColor,
          Color.lerp(a.skin.dangerColor, b.skin.dangerColor, 0.5));
    });

    test('copyWith 单字段覆盖', () {
      const skin = AppThemeScheme.snowMiku;
      final changed = skin.skin.copyWith(dangerColor: const Color(0xFF000000));
      expect(changed.dangerColor, const Color(0xFF000000));
      expect(changed.focusRingColor, skin.skin.focusRingColor);
      expect(changed.accentColor, skin.skin.accentColor);
    });
  });
}
