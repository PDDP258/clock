/// 设备画像：识别「这台设备是不是 M500」（纯 Dart，可单测）。
///
/// 两个独立信号（2026-10-01 用户口径：**两个都不满足才算非 M500**）：
///
/// 1. **比例信号** [isM500LikeRatio]：横屏宽高比 ≈ 16:9（M500 = 1280×720）。
///    允许小容差——同为 5 英寸 720p 的贴牌/换屏机型比例不会变；
///    手机（19.5:9 ~ 21:9）和平板（4:3 / 16:10）都会被排除。
/// 2. **机型信号** [looksLikeM500Model]：`Build.MODEL / DEVICE / PRODUCT`
///    里含 `m500`（不区分大小写）。防「比例凑巧 16:9 的他厂设备」误判，
///    也防 M500 特殊固件上报了别的分辨率。
///
/// 任一信号命中即视为 M500 → 计时页**不**显示触屏侧键（M500 有实体键，
/// 且 5 英寸屏幕寸土寸金）；两个都未命中 → 显示左右触屏按钮
/// （[showTouchSideControls]），供无实体键的普通设备使用。
///
/// 顺带提供横屏「余光」布局的缩放系数 [uiScaleFor]：布局以 M500 的
/// 逻辑高（720 物理 / dpr≈1.835 ≈ 392.5 逻辑像素）为基准，按实际
/// 视口高度等比缩放并夹在 [kUiScaleMin, kUiScaleMax]——
/// 这就是「自动适应比例」的锚点：高度变了整体缩放，宽度自然流动。
library;

import 'dart:math' as math;

/// M500 物理分辨率（横屏）。
const double kM500Width = 1280;

/// M500 物理分辨率（横屏）。
const double kM500Height = 720;

/// M500 屏幕比例（16:9 ≈ 1.778）。
const double kM500Ratio = kM500Width / kM500Height;

/// 比例判定的容差（±3%）：覆盖 16:9 附近的舍入与裁切屏
/// （挖孔屏 app 内可用区可能比物理比例略窄一点）。
const double kM500RatioTolerance = 0.03;

/// M500 的逻辑高基准（720 / dpr 1.835 ≈ 392.5）。
const double kUiBaseLogicalHeight = 392.5;

/// 缩放下限：比 M500 更矮的小屏不无限缩小，保住可触性。
const double kUiScaleMin = 0.85;

/// 缩放上限：平板/桌面横屏不无限放大，cap 住装饰性尺寸。
const double kUiScaleMax = 1.8;

/// 横屏宽高比是否与 M500（16:9）一致（在容差内）。
///
/// 竖屏（w < h）恒为 false——M500 锁定横屏，竖屏姿态直接按非 M500 处理。
bool isM500LikeRatio(double width, double height,
    {double tolerance = kM500RatioTolerance}) {
  if (width <= 0 || height <= 0 || width < height) return false;
  final ratio = width / height;
  return (ratio - kM500Ratio).abs() <= tolerance * kM500Ratio;
}

/// 机型标识是否指向 M500（任一字段含 `m500` 即命中，不区分大小写）。
///
/// M500 贴牌机型可能 MODEL 是营销名而 DEVICE/PRODUCT 保留代号，
/// 故三个字段都参与。空白安全：null/空串不抛错、不命中。
bool looksLikeM500Model({
  String? model,
  String? device,
  String? product,
  String? manufacturer,
}) {
  bool hit(String? s) {
    if (s == null) return false;
    return s.toLowerCase().contains('m500');
  }

  return hit(model) || hit(device) || hit(product) || hit(manufacturer);
}

/// 是否显示计时页触屏侧键：**比例与机型两个信号都不满足**才显示
/// （2026-10-01 用户口径）。任一命中 M500 都说明机器有实体键方案，
/// 屏幕两侧保持干净。
bool showTouchSideControls({
  required bool ratioLikeM500,
  required bool deviceIsM500,
}) =>
    !ratioLikeM500 && !deviceIsM500;

/// 「余光」布局缩放系数：实际逻辑高 ÷ M500 基准高，夹在
/// [kUiScaleMin, kUiScaleMax]。
///
/// 高度是横屏布局的约束边（时钟按屏高定大小），用它当锚点后，
/// 无论手机（393 逻辑高 ≈ 1.0）、平板还是桌面窗口，各元素
/// 相对比例都与 M500 一致。
double uiScaleFor(double logicalHeight,
        {double base = kUiBaseLogicalHeight,
        double min = kUiScaleMin,
        double max = kUiScaleMax}) =>
    (logicalHeight / base).clamp(min, max).toDouble();

/// 便捷组合：由视口尺寸直接得缩放系数（取宽高较小者当「高」，
/// 这样竖屏窗口也能正确缩放）。
double uiScaleForSize(double width, double height) =>
    uiScaleFor(math.min(width, height));
