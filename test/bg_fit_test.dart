/// 背景适配规则的边界测试（`lib/core/background/bg_fit.dart`）。
///
/// 这组测试的重点是**判定必须精确**：
/// - 阈值是 **1.3**（2026-10-01 调参，原为屏幕比例 16/9），正好 1.3 的图
///   （`1300×1000`）必须落在规则 1；
/// - 判定用整数交叉相乘，浮点比较会在这些值上抖动；
/// - `cover` 的解必须**恰好有一边等于视口边长**，否则「刚好铺满」不成立。
library;

import 'package:ai_clock/core/background/bg_fit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bgRuleOf：规则判定（阈值 1.3）', () {
    test('正好 1.3 落在规则 1（判定必须精确到边界）', () {
      // 1300×1000 与 13×10 同比例：浮点除法若抖动就会判错，故用交叉相乘
      expect(bgRuleOf(1300, 1000), BgFitRule.fillHeight);
      // 差一个像素就该掉到规则 2
      expect(bgRuleOf(1299, 1000), BgFitRule.fillWidth);
    });

    test('比 1.3 更宽 → 规则 1（含原 16:9 那批）', () {
      expect(bgRuleOf(2160, 1080), BgFitRule.fillHeight); // 2.0
      expect(bgRuleOf(4406, 2203), BgFitRule.fillHeight); // 1.9999…
      expect(bgRuleOf(2066, 1080), BgFitRule.fillHeight);
      // 16:9 与更宽的源图（这两个是真实源图里的值）
      expect(bgRuleOf(1920, 1080), BgFitRule.fillHeight);
      expect(bgRuleOf(2048, 1152), BgFitRule.fillHeight);
      // 1.3 ~ 16:9 之间：新阈值下归规则 1（2026-10-01 调参的核心变化）
      expect(bgRuleOf(1528, 1080), BgFitRule.fillHeight); // 1.415
      expect(bgRuleOf(1800, 1080), BgFitRule.fillHeight); // 1.667
    });

    test('比 1.3 更窄（含竖构图、方图）→ 规则 2', () {
      expect(bgRuleOf(1280, 1000), BgFitRule.fillWidth); // 1.28，差一点点
      expect(bgRuleOf(1280, 1280), BgFitRule.fillWidth); // 方图
      expect(bgRuleOf(1280, 1856), BgFitRule.fillWidth);
      expect(bgRuleOf(1024, 2336), BgFitRule.fillWidth);
    });

    test('非法尺寸不抛异常（默认按规则 1 处理，渲染层会直接跳过）', () {
      expect(bgRuleOf(0, 100), BgFitRule.fillHeight);
      expect(bgRuleOf(100, 0), BgFitRule.fillHeight);
      expect(bgRuleOf(-1, -1), BgFitRule.fillHeight);
    });

    test('bgFollowsScroll 只对规则 2 为真', () {
      expect(bgFollowsScroll(2160, 1080), isFalse);
      expect(bgFollowsScroll(1280, 1856), isTrue);
    });

    test('规则标签是非空中文（设置页/登记表共用）', () {
      for (final rule in BgFitRule.values) {
        expect(rule.label, isNotEmpty);
        expect(rule.targetLabel, isNotEmpty);
      }
    });
  });

  group('bgTargetSize：入库目标（只缩不放）', () {
    test('规则 1 按高缩到 1080，宽度按比例', () {
      final size = bgTargetSize(4406, 2203);
      expect(size.height, kBgRule1TargetHeight);
      expect(size.width, (4406 * 1080 / 2203).round());
    });

    test('规则 2 按宽缩到 1280，高度按比例', () {
      final size = bgTargetSize(2480, 3508);
      expect(size.width, kBgRule2TargetWidth);
      expect(size.height, (3508 * 1280 / 2480).round());
    });

    test('源比目标小时不放大（避免把模糊像素再拉一遍）', () {
      // 1024 宽 < 1280 目标宽：保持原尺寸
      expect(bgTargetSize(1024, 2336), (width: 1024, height: 2336));
      // 高度不足 1080 的规则 1 图：保持原样
      expect(bgTargetSize(2000, 900), (width: 2000, height: 900));
    });

    test('长边受 kBgMaxEdge 约束（超长图按长边回落）', () {
      final size = bgTargetSize(1000, 20000);
      expect(size.height, kBgMaxEdge);
      expect(size.width, (1000 * kBgMaxEdge / 20000).round());
    });

    test('非法尺寸返回 1×1 而不是 0 或负数', () {
      expect(bgTargetSize(0, 0), (width: 1, height: 1));
      expect(bgTargetSize(-5, 10), (width: 1, height: 1));
    });
  });

  group('bgCoverSize：cover + 顶部对齐的解', () {
    const viewW = 640.0;
    const viewH = 360.0; // 逻辑像素的 16:9

    test('规则 1：高度刚好等于视口高，宽度溢出', () {
      final size = bgCoverSize(
          imageWidth: 2160,
          imageHeight: 1080,
          viewWidth: viewW,
          viewHeight: viewH);
      expect(size.height, closeTo(viewH, 0.001));
      expect(size.width, greaterThan(viewW));
    });

    test('规则 2：宽度刚好等于视口宽，高度溢出', () {
      final size = bgCoverSize(
          imageWidth: 1280,
          imageHeight: 1856,
          viewWidth: viewW,
          viewHeight: viewH);
      expect(size.width, closeTo(viewW, 0.001));
      expect(size.height, greaterThan(viewH));
    });

    test('永远铺满：两边都不小于视口，且恰好有一边相等', () {
      const cases = [
        (2160, 1080),
        (2066, 1080),
        (1280, 769),
        (1280, 2560),
        (1024, 2336),
        (1280, 1280),
        (1280, 720),
      ];
      for (final (w, h) in cases) {
        final size = bgCoverSize(
            imageWidth: w.toDouble(),
            imageHeight: h.toDouble(),
            viewWidth: viewW,
            viewHeight: viewH);
        expect(size.width, greaterThanOrEqualTo(viewW - 0.001),
            reason: '$w×$h 宽度没铺满');
        expect(size.height, greaterThanOrEqualTo(viewH - 0.001),
            reason: '$w×$h 高度没铺满');
        final oneSideExact =
            (size.width - viewW).abs() < 0.001 ||
                (size.height - viewH).abs() < 0.001;
        expect(oneSideExact, isTrue, reason: '$w×$h 没有「刚好」的那一边');
      }
    });

    test('非法输入回退视口尺寸（不抛，不给 NaN）', () {
      final size = bgCoverSize(
          imageWidth: 0, imageHeight: 0, viewWidth: viewW, viewHeight: viewH);
      expect(size.width, viewW);
      expect(size.height, viewH);
    });
  });

  group('bgScrollExtent：背景可滚多远', () {
    const viewW = 640.0;
    const viewH = 360.0;

    test('规则 1 恒为 0（背景钉住不动）', () {
      expect(
          bgScrollExtent(
              imageWidth: 2160,
              imageHeight: 1080,
              viewWidth: viewW,
              viewHeight: viewH),
          0);
    });

    test('规则 2 = 纵向溢出量，且随图越高越大', () {
      // 1280×1000（1.28，刚够规则 2）：按宽缩到 640 之后高 500 → 溢出 140
      final shallow = bgScrollExtent(
          imageWidth: 1280,
          imageHeight: 1000,
          viewWidth: viewW,
          viewHeight: viewH);
      final deep = bgScrollExtent(
          imageWidth: 1280,
          imageHeight: 2560,
          viewWidth: viewW,
          viewHeight: viewH);
      expect(shallow, greaterThan(0));
      expect(deep, greaterThan(shallow));
      // 1280×2560 按宽缩到视口宽 640 时高度是 1280 → 溢出 1280-360=920
      expect(deep, closeTo(920, 0.001));
    });
  });
}
