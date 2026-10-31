/// 背景图适配规则（纯 Dart，与 `tool/miku_bg_prepare.py` 同源）。
///
/// M500 锁定横屏（`sensorLandscape`），物理分辨率 **1280 × 720**
/// （屏幕长边比短边 `S = 1280/720 = 16/9`，渲染几何仍以它为准）。
///
/// **分类阈值与屏幕比例是两件事**（2026-10-01 用户调参：阈值改 1.3）：
///
/// - **规则 1** `w/h >= 1.3`：归「规则 1 池」。渲染时按 `cover` 铺满：
///   - `r >= 16/9` 的那部分（4 张）→ 高度刚好铺满、**纵向无溢出** → 背景固定不动；
///   - `1.3 <= r < 16/9` 的那部分（7 张）→ 屏幕比图更宽，cover 只能按宽铺满，
///     纵向溢出 28~265px → 仍会随滚动（幅度很小）。几何如此，改阈值改不了。
/// - **规则 2** `w/h < 1.3`：归「规则 2 池」。缩放到**宽度刚好铺满**、
///   纵向溢出较大（265~1840px）→ 顶置并随内容 1:1 下移。
///
/// 两条规则在渲染上都是 `BoxFit.cover` + 顶部对齐（[Alignment.topCenter]），
/// 区别只在**归到哪个池**以及由此产生的溢出量——溢出方向决定了要不要跟着滚动，
/// 这也是本文件只做「判定 + 尺寸换算」两件事、不做渲染的原因。
///
/// 口径来源：`docs/10-背景图库登记表.md`。改基准时两处一起改。
library;

import 'dart:math' as math;

/// 屏幕基准宽（M500 物理像素）。
const int kBgScreenWidth = 1280;

/// 屏幕基准高（M500 物理像素）。
const int kBgScreenHeight = 720;

/// **分类阈值：1.3**（2026-10-01 用户调参，原为屏幕比例 16/9）。
///
/// 以分数 `13/10` 存储，判定用整数交叉相乘（`w * 10 >= h * 13`），
/// 与浮点比较 `w/h >= 1.3` 等价但没有舍入抖动。
const int kBgRuleRatioNum = 13;

/// 分类阈值分母（见 [kBgRuleRatioNum]）。
const int kBgRuleRatioDen = 10;

/// 分类阈值的浮点视图（文档/展示/预处理脚本同源常量）。
const double kBgRuleRatio = kBgRuleRatioNum / kBgRuleRatioDen;

/// 入库目标高度：规则 1 按高缩放的目标（渲染只用到 720，留 1.5x 抗锯齿余量）。
const int kBgRule1TargetHeight = 1080;

/// 入库目标宽度：规则 2 按宽缩放的目标（= 屏幕宽，渲染时 1:1 落屏）。
const int kBgRule2TargetWidth = 1280;

/// 单边长上限（解码内存护栏，与预处理脚本一致）。
const int kBgMaxEdge = 4096;

/// 背景不透明度：统计两页（图片直接压在页面底色上）。
///
/// 调参历史：40% → 50%（2026-09-30）→ 60%（2026-10-01）。
const double kBgOpacityStats = 0.60;

/// 背景不透明度：计时页（图片压在**阶段染色**之上，更低以免盖掉一眼信号）。
///
/// 调参历史：30% → 40%（2026-09-30）→ 50% → 45%（2026-10-01 同轮再减 5%）。
const double kBgOpacityFocus = 0.45;

/// 计时页背景图额外掺白的比例（2026-10-01 用户调参：再变白 8%）。
///
/// 走 `Image.color` + `BlendMode.srcATop`：色滤镜先作用于图像像素
/// （等价于向白色掺 8%），再乘 [kBgOpacityFocus] 的 alpha，零额外图层。
const double kBgFocusWhiten = 0.08;

/// 统计两页卡片色块（「黑色圆角矩形」）的不透明度。
///
/// 调参历史：55% → 25%（2026-09-30）→ 15%（2026-10-01，同步把底色
/// 调白了一点点，见 `backdropPanelColor`）。
const double kBgPanelOpacity = 0.15;

/// 适配规则。
enum BgFitRule {
  /// 规则 1：比例 ≥ 1.3 → 归规则 1 池（其中 ≥16:9 的部分真正高铺满、固定）。
  fillHeight,

  /// 规则 2：比例 < 1.3 → 归规则 2 池，宽度刚好铺满、纵向溢出 → 随内容滚动。
  fillWidth;

  /// 中文标签（设置页/调试用）。
  String get label => switch (this) {
        BgFitRule.fillHeight => '规则 1 · 高铺满',
        BgFitRule.fillWidth => '规则 2 · 宽铺满 · 随滚动',
      };

  /// 该规则入库时的目标高度说明（登记表/设置页共用）。
  String get targetLabel => switch (this) {
        BgFitRule.fillHeight => '按高缩放到 $kBgRule1TargetHeight',
        BgFitRule.fillWidth => '按宽缩放到 $kBgRule2TargetWidth',
      };
}

/// 判定适配规则（阈值 [kBgRuleRatio] = 1.3）。
///
/// 用**整数交叉相乘**而不是浮点比例比较：`1300×1000` 这类正好等于 1.3 的图，
/// 浮点除法与 `13/10` 是否相等取决于舍入方向，判定会抖动；
/// 交叉相乘是精确整数运算，没有这个问题。
BgFitRule bgRuleOf(int width, int height) {
  if (width <= 0 || height <= 0) return BgFitRule.fillHeight;
  return width * kBgRuleRatioDen >= height * kBgRuleRatioNum
      ? BgFitRule.fillHeight
      : BgFitRule.fillWidth;
}

/// 背景是否随内容滚动（= 规则 2）。
bool bgFollowsScroll(int width, int height) =>
    bgRuleOf(width, height) == BgFitRule.fillWidth;

/// 入库目标尺寸（与预处理脚本 [target_size] 同源）。
///
/// **只缩不放**：源比目标小就保持原尺寸——硬拉到目标只会多花体积，
/// 对着被放大的模糊像素再放大一次不会变清楚。长边超 [kBgMaxEdge] 时
/// 按长边回落，保证单张解码内存可控。
({int width, int height}) bgTargetSize(int width, int height) {
  if (width <= 0 || height <= 0) return (width: 1, height: 1);
  final rule = bgRuleOf(width, height);
  final want = switch (rule) {
    BgFitRule.fillHeight => kBgRule1TargetHeight / height,
    BgFitRule.fillWidth => kBgRule2TargetWidth / width,
  };
  final scale = math.min(want, 1.0);
  var w = math.max(1, (width * scale).round());
  var h = math.max(1, (height * scale).round());
  final longest = math.max(w, h);
  if (longest > kBgMaxEdge) {
    final back = kBgMaxEdge / longest;
    w = math.max(1, (w * back).round());
    h = math.max(1, (h * back).round());
  }
  return (width: w, height: h);
}

/// 实际渲染尺寸（`BoxFit.cover` + 顶部对齐的解，显式算出来供测试与布局用）。
///
/// [imageWidth]/[imageHeight] 是图片（或解码后）的像素尺寸，
/// [viewWidth]/[viewHeight] 是页面可视区尺寸（逻辑像素即可，cover 只依赖比值）。
///
/// 返回值保证：宽 >= viewWidth 且高 >= viewHeight（永远铺满、不留白），
/// 且**恰好有一边相等**——相等的那一边就是规则里「刚好铺满」的那一边。
({double width, double height}) bgCoverSize({
  required double imageWidth,
  required double imageHeight,
  required double viewWidth,
  required double viewHeight,
}) {
  if (imageWidth <= 0 ||
      imageHeight <= 0 ||
      viewWidth <= 0 ||
      viewHeight <= 0) {
    return (width: viewWidth, height: viewHeight);
  }
  final scale = math.max(viewWidth / imageWidth, viewHeight / imageHeight);
  return (width: imageWidth * scale, height: imageHeight * scale);
}

/// 背景可滚动的最大距离（= 纵向溢出量）；规则 1 恒为 0（背景固定）。
///
/// 页面自身内容可能比这个值更短，实际可滚距离取两者较小值。
double bgScrollExtent({
  required int imageWidth,
  required int imageHeight,
  required double viewWidth,
  required double viewHeight,
}) {
  if (!bgFollowsScroll(imageWidth, imageHeight)) return 0;
  final size = bgCoverSize(
    imageWidth: imageWidth.toDouble(),
    imageHeight: imageHeight.toDouble(),
    viewWidth: viewWidth,
    viewHeight: viewHeight,
  );
  return math.max(0, size.height - viewHeight);
}
