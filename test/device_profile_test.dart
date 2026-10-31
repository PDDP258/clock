/// 设备画像识别的单测（看板 #56）。
///
/// 只测纯 Dart 公开行为：比例判定、机型判定、侧键显示条件、缩放系数。
/// 原生通道（Build.MODEL 上报）不进单测——按项目 §6-5 接缝约定，
/// 靠 analyze + 真机验收。
library;

import 'package:ai_clock/core/platform/device_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isM500LikeRatio：比例信号', () {
    test('M500 本尊（1280×720）与同比例分辨率命中', () {
      expect(isM500LikeRatio(1280, 720), isTrue);
      expect(isM500LikeRatio(1920, 1080), isTrue);
      expect(isM500LikeRatio(2560, 1440), isTrue);
      // 逻辑像素（dpr 1.835 后的 697×392.5）也要命中——判定用的是
      // MediaQuery 逻辑尺寸，不是物理像素
      expect(isM500LikeRatio(697, 392.5), isTrue);
    });

    test('容差内（±3%）命中：挖孔屏可用区略窄于 16:9 也算', () {
      // 16:9 × (1 - 0.03) ≈ 1.725
      expect(isM500LikeRatio(1725, 1000), isTrue);
      // 16:9 × (1 + 0.03) ≈ 1.831
      expect(isM500LikeRatio(1831, 1000), isTrue);
    });

    test('手机长条屏（19.5:9 ~ 21:9）不命中', () {
      expect(isM500LikeRatio(2340, 1080), isFalse); // 19.5:9 ≈ 2.167
      expect(isM500LikeRatio(2400, 1080), isFalse); // 20:9 = 2.222
      // 用户截图设备：可见区约 2.1~2.3
      expect(isM500LikeRatio(1080, 508), isFalse);
    });

    test('平板比例（4:3 / 16:10）不命中', () {
      expect(isM500LikeRatio(1024, 768), isFalse);
      expect(isM500LikeRatio(1280, 800), isFalse);
    });

    test('竖屏姿态恒不命中（M500 锁定横屏）', () {
      expect(isM500LikeRatio(720, 1280), isFalse);
      expect(isM500LikeRatio(392.5, 697), isFalse);
    });

    test('非法尺寸安全返回 false', () {
      expect(isM500LikeRatio(0, 720), isFalse);
      expect(isM500LikeRatio(1280, 0), isFalse);
      expect(isM500LikeRatio(-1, -1), isFalse);
    });

    test('正方形不命中', () {
      expect(isM500LikeRatio(1000, 1000), isFalse);
    });
  });

  group('looksLikeM500Model：机型信号', () {
    test('任一字段含 m500（不区分大小写）即命中', () {
      expect(looksLikeM500Model(model: 'M500'), isTrue);
      expect(looksLikeM500Model(model: 'miku-m500-360p'), isTrue);
      expect(looksLikeM500Model(device: 'M500'), isTrue);
      expect(looksLikeM500Model(product: 'm500_user'), isTrue);
      expect(looksLikeM500Model(manufacturer: 'MikuM500'), isTrue);
    });

    test('贴牌机型：MODEL 是营销名、代号在 device/product', () {
      expect(
        looksLikeM500Model(model: 'Miku Focus Clock', device: 'm500'),
        isTrue,
      );
    });

    test('他厂设备不命中', () {
      expect(looksLikeM500Model(model: '2211133G'), isFalse);
      expect(looksLikeM500Model(model: 'Pixel 8'), isFalse);
      expect(
        looksLikeM500Model(
          model: 'SM-G9910',
          device: 'o1s',
          product: 'o1skx',
          manufacturer: 'samsung',
        ),
        isFalse,
      );
    });

    test('空白安全：null / 空串不命中也不抛错', () {
      expect(looksLikeM500Model(), isFalse);
      expect(looksLikeM500Model(model: '', device: ''), isFalse);
    });
  });

  group('showTouchSideControls：两个信号都不满足才显示', () {
    test('真值表', () {
      // M500 本尊：比例 + 机型都命中 → 不显示
      expect(
        showTouchSideControls(ratioLikeM500: true, deviceIsM500: true),
        isFalse,
      );
      // 比例凑巧 16:9 的他厂设备 → 不显示（有余光布局就够）
      expect(
        showTouchSideControls(ratioLikeM500: true, deviceIsM500: false),
        isFalse,
      );
      // M500 固件上报异常分辨率（机型兜底）→ 不显示
      expect(
        showTouchSideControls(ratioLikeM500: false, deviceIsM500: true),
        isFalse,
      );
      // 普通手机/平板：两个信号都不满足 → 显示
      expect(
        showTouchSideControls(ratioLikeM500: false, deviceIsM500: false),
        isTrue,
      );
    });
  });

  group('uiScaleFor：视口高度缩放', () {
    test('M500 基准（392.5 逻辑高）= 1.0，历史调参值原样保留', () {
      expect(uiScaleFor(392.5), 1.0);
    });

    test('等比：1.5 倍高 = 1.5 倍缩放（未触顶时）', () {
      // 392.5 × 1.5 = 588.75 < 1.8 上限
      expect(uiScaleFor(588.75), closeTo(1.5, 0.0001));
    });

    test('夹在下限 0.85：比 M500 更矮的小屏不再缩小', () {
      expect(uiScaleFor(300), kUiScaleMin);
      expect(uiScaleFor(1), kUiScaleMin);
    });

    test('夹在上限 1.8：平板/桌面不无限放大', () {
      expect(uiScaleFor(1200), kUiScaleMax);
    });

    test('uiScaleForSize 取短边（横屏=高，竖屏=宽）', () {
      expect(uiScaleForSize(697, 392.5), 1.0);
      expect(uiScaleForSize(392.5, 697), 1.0);
    });
  });
}
