/// 图库禁用集：候选池剔除逻辑（2026-10-05 图库管理）。
library;

import 'package:ai_clock/core/background/bg_image.dart';
import 'package:ai_clock/features/backgrounds/application/background_controller.dart';
import 'package:flutter_test/flutter_test.dart';

BgImage _img(String id, int w, int h, {bool bundled = true}) => BgImage(
      id: id,
      ref: bundled ? 'assets/backgrounds/$id.webp' : '/x/$id.webp',
      bundled: bundled,
      width: w,
      height: h,
    );

void main() {
  group('bgExcludeDisabled', () {
    final library = BgLibrary([
      _img('bg_a', 1600, 900), // 规则 1
      _img('bg_b', 1000, 1200), // 规则 2
      _img('u_c', 1280, 720, bundled: false), // 规则 1
    ]);

    test('空禁用集原样返回', () {
      final out = bgExcludeDisabled(library, <String>{});
      expect(identical(out, library), isTrue);
    });

    test('剔除禁用图，池构成随之变化', () {
      final out = bgExcludeDisabled(library, {'bg_b'});
      expect(out.images.map((i) => i.id), ['bg_a', 'u_c']);
      expect(out.scrollablePool, isEmpty); // 规则 2 池只有 bg_b，被禁后为空
      expect(out.fixedPool.length, 2);
    });

    test('全部禁用 = 空池（各页退纯色）', () {
      final out = bgExcludeDisabled(library, {'bg_a', 'bg_b', 'u_c'});
      expect(out.isEmpty, isTrue);
    });

    test('禁用集含不存在的 id 不报错', () {
      final out = bgExcludeDisabled(library, {'ghost', 'bg_a'});
      expect(out.images.map((i) => i.id), ['bg_b', 'u_c']);
    });
  });
}
