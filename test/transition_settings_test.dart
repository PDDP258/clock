import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clock/features/focus/application/transition_settings.dart';

/// 轮次转场强度档位（看板 #62）。
///
/// 覆盖点：持久化解析的三条口径——正常值、缺失回退、**坏值也回退**
/// （老用户不会因为一个坏键值卡在「关闭」上）。
void main() {
  group('转场强度档位解析', () {
    test('三档都能按 name 往返', () {
      for (final v in TransitionIntensity.values) {
        expect(transitionIntensityFromName(v.name), v);
      }
    });

    test('缺失 / 空串 / 坏值 → 完整档（不静默降级为关闭）', () {
      expect(transitionIntensityFromName(null), TransitionIntensity.full);
      expect(transitionIntensityFromName(''), TransitionIntensity.full);
      expect(transitionIntensityFromName('nope'), TransitionIntensity.full);
      // 大小写敏感：只认 enum name，不做模糊匹配
      expect(transitionIntensityFromName('FULL'), TransitionIntensity.full);
    });

    test('显示文案齐全（设置页直接用 label/hint，不做二次映射）', () {
      for (final v in TransitionIntensity.values) {
        expect(v.label, isNotEmpty);
        expect(v.hint, isNotEmpty);
        expect(v.wire, v.name);
      }
      // 顺序即设置页展示顺序：完整 → 精简 → 关闭
      expect(TransitionIntensity.values.map((v) => v.wire).toList(),
          <String>['full', 'lite', 'off']);
    });
  });
}
