/// 背景渲染（presentation 层）：两条规则的唯一落地点。
///
/// 一个 [BackdropLayer] 铺满父级，按 `docs/10` 的两条规则画图：
///
/// | 规则 | 显示尺寸 | 对齐 | 滚动 |
/// | --- | --- | --- | --- |
/// | 1（比 16:9 更宽） | 高 = 视口高，宽溢出 | 顶部居中 | **固定**（[maxScroll] = 0） |
/// | 2（比 16:9 更窄） | 宽 = 视口宽，高溢出 | 顶部居中 | **跟随**内容 1:1，最多到 [maxScroll] 为止 |
///
/// 两个实现要点：
/// 1. **不透明度走 `Image.opacity` 而不是外层 `Opacity`**：后者会为一个
///    1280×2560 的图层开 `saveLayer`，在 M500 上白白吃掉十几 MB 纹理；
///    `Image.opacity` 只是把 alpha 乘进画笔，零额外图层。
/// 2. **滚动位移必须夹到 [maxScroll]**：页面内容往往比图片高得多，
///    不夹住的话滚到后面背景就滑出屏幕、露出空白。夹住之后
///    「图片滚完了就停住」——这也是规则 1 天然退化成固定的原因。
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/background/bg_fit.dart';
import '../../../core/background/bg_image.dart';
import '../application/background_controller.dart';

/// 背景图层：填满父级，画在父级已有的底色之上。
///
/// [scrollOffset] 非空时按规则跟随（内容滚动偏移，逻辑像素）；
/// 传 null 表示这个页面不滚动（如计时页），图片恒为顶部对齐的静止层。
class BackdropLayer extends StatelessWidget {
  const BackdropLayer({
    super.key,
    required this.spec,
    this.scrollOffset,
  });

  /// 当前该画什么（纯色时直接不画）
  final BackdropSpec spec;

  /// 内容滚动偏移；null = 静止
  final ValueListenable<double>? scrollOffset;

  /// 换图时的淡入时长（一次性动画，符合余光「慢或一次性」的动画纪律）
  static const Duration fadeIn = Duration(milliseconds: 600);

  @override
  Widget build(BuildContext context) {
    final image = spec.image;
    if (image == null || !spec.hasImage) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewWidth = constraints.maxWidth;
        final viewHeight = constraints.maxHeight;
        if (viewWidth <= 0 || viewHeight <= 0) {
          return const SizedBox.shrink();
        }

        // 显示尺寸与可滚动余量都按规则算（规则 1 的 maxScroll 恒为 0）
        final size = bgCoverSize(
          imageWidth: image.width.toDouble(),
          imageHeight: image.height.toDouble(),
          viewWidth: viewWidth,
          viewHeight: viewHeight,
        );
        final maxScroll = bgScrollExtent(
          imageWidth: image.width,
          imageHeight: image.height,
          viewWidth: viewWidth,
          viewHeight: viewHeight,
        );

        final layer = SizedBox(
          width: size.width,
          height: size.height,
          child: _buildImage(image),
        );

        // OverflowBox：让超出视口的那一边保持自身尺寸（默认会被压缩回去）
        Widget content = OverflowBox(
          alignment: Alignment.topCenter,
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          child: layer,
        );

        final listenable = scrollOffset;
        if (listenable != null && maxScroll > 0) {
          content = ValueListenableBuilder<double>(
            valueListenable: listenable,
            // 位移夹在 [0, maxScroll]：滚过图片高度后背景停住
            builder: (context, offset, child) => Transform.translate(
              offset: Offset(0, -offset.clamp(0.0, maxScroll)),
              child: child,
            ),
            child: content,
          );
        }

        return ClipRect(child: content);
      },
    );
  }

  Widget _buildImage(BgImage image) {
    return Image(
      image: _providerOf(image),
      width: double.infinity,
      height: double.infinity,
      // 尺寸已按 cover 精确算好，fill 不会变形（只做等比缩放）
      fit: BoxFit.fill,
      // 不透明度乘进画笔，避免额外图层（见文件头说明）
      opacity: AlwaysStoppedAnimation<double>(spec.opacity),
      // 掺白：色滤镜先作用于图像像素（= 向白色掺 whiten），再乘上面的
      // alpha，零额外图层。srcATop 会保留图像自身的 alpha，不会挖洞。
      color: spec.whiten > 0
          ? Colors.white.withValues(alpha: spec.whiten)
          : null,
      colorBlendMode: spec.whiten > 0 ? BlendMode.srcATop : null,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: fadeIn,
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }

  /// 内置走 asset、用户走文件（三元的静态类型会是 Object，故用语句返回）。
  ImageProvider _providerOf(BgImage image) => bgImageProvider(image);
}

/// 取一张图的 [ImageProvider]：内置走 asset、用户走文件。
///
/// 三元的静态类型会被推断成 Object，故用 if 语句分别返回。
ImageProvider<Object> bgImageProvider(BgImage image) {
  if (image.bundled) return AssetImage(image.ref);
  return FileImage(File(image.ref));
}

/// 可滚动页面的背景容器：背景铺满自身，内容叠在上面滚动。
///
/// 用法（统计两页）：把原来的 `body` 直接套进来，并把 AppBar 设为透明 +
/// `extendBodyBehindAppBar: true`，内容顶部留出 `kToolbarHeight` 的内边距。
class ScrollAwareBackground extends ConsumerStatefulWidget {
  const ScrollAwareBackground({
    super.key,
    required this.page,
    required this.child,
  });

  /// 哪一页（决定抽图策略与不透明度）
  final BgPage page;

  /// 页面内容（内含唯一的可滚动区）
  final Widget child;

  @override
  ConsumerState<ScrollAwareBackground> createState() =>
      _ScrollAwareBackgroundState();
}

class _ScrollAwareBackgroundState extends ConsumerState<ScrollAwareBackground> {
  /// 内容滚动偏移（背景层据此平移；只在背景层重建，不波及内容）
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = ref.watch(backdropProvider(widget.page));
    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropLayer(spec: spec, scrollOffset: _offset),
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _offset.value = notification.metrics.pixels;
            return false; // 继续向上冒泡
          },
          child: widget.child,
        ),
      ],
    );
  }
}

/// 静止背景层（计时页用）：不接滚动，图片恒为顶部对齐。
///
/// 计时页把它放进阶段染色容器**之内**，于是图层顺序天然是
/// 「阶段染色 → 图片 → 内容」——正是 `docs/10` §3 要求的顺序。
class StaticBackdrop extends ConsumerWidget {
  const StaticBackdrop({super.key, required this.page});

  final BgPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BackdropLayer(spec: ref.watch(backdropProvider(page)));
  }
}

/// 透明 AppBar 的统一样式（背景要透到状态栏与标题栏后面）。
///
/// 用 [SystemUiOverlayStyle] 之外的纯色透明即可：M500 是深色主题常驻，
/// 标题/图标沿用主题的前景色，压在图片上依然可读（图片只有 40%/30%）。
AppBar transparentAppBar({required String title, List<Widget>? actions}) {
  return AppBar(
    title: Text(title),
    actions: actions,
    backgroundColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
  );
}

/// 内容顶部需要留出的高度（透明 AppBar 会盖住内容，必须自己让位）。
double appBarTopPadding(BuildContext context) =>
    MediaQuery.paddingOf(context).top + kToolbarHeight;

/// 半透明卡片「色块」颜色。
///
/// 图层顺序（`docs/10` §3）：**页面底色 → 背景图 → 卡片色块 → 文字**。
/// 卡片必须半透明，图片才透得上来。不透明度 [kBgPanelOpacity]
/// （调参历史 55%→25%→15%，2026-10-01 同步把底色调白了一点点：
/// 纯 surface 近黑，压在 60% 的图上几乎只剩「变暗」，掺 8% 白
/// 才有「蒙一层浅色」的层次感，文字对比也托得住）。
Color backdropPanelColor(BuildContext context, {Color? tint}) {
  final base = Theme.of(context).colorScheme.surface;
  final tinted = tint == null
      ? base
      : Color.alphaBlend(tint.withValues(alpha: 0.18), base);
  // 「稍微变白一点点」：向白色掺 8%（在 alpha 混合之前完成，
  // 保证 tint 卡片与普通卡片同步变白）
  return Color.alphaBlend(Colors.white.withValues(alpha: 0.08), tinted)
      .withValues(alpha: kBgPanelOpacity);
}
