/// 背景图库的模型与清单解析（纯 Dart）。
///
/// 两个来源、两套清单、一个候选池：
///
/// | 来源 | 清单 | 存放 | 可写 |
/// | --- | --- | --- | --- |
/// | 内置图库 | `assets/backgrounds/manifest.json` | 打包进 APK | 否 |
/// | 用户图库 | `backgrounds/user_manifest.json` | 应用专属外存 | 是 |
///
/// 两份清单**结构相同**（都是 [kBgLibrarySchemaId]），所以解析只有一份实现；
/// 差别只在 [BgImage.bundled] 为真时 [BgImage.ref] 是 asset key，
/// 为假时是绝对文件路径。分类与适配规则一律**从尺寸现算**
/// （[BgImage.rule]）而不信任清单里的字段——清单是产物，尺寸才是事实。
library;

import 'dart:convert';

import 'bg_fit.dart';

/// 清单 schema 标识（两份清单共用）。
const String kBgLibrarySchemaId = 'aiclock.bg_library/1';

/// 内置图库清单的 asset key。
const String kBgBundledManifestAsset = 'assets/backgrounds/manifest.json';

/// 用户图库清单文件名（应用专属外存 `backgrounds/` 目录内）。
const String kBgUserManifestFileName = 'user_manifest.json';

/// 用户图库素材目录名（相对应用专属外存根）。
const String kBgUserImageDirName = 'backgrounds';

/// 用户图片 id 前缀（与内置的 `bg_` 不会撞号）。
const String kBgUserIdPrefix = 'u_';

/// 几何分类——直接映射适配规则与观感，也正是选图时要用的维度。
///
/// 阈值随 `docs/10` §5：2026-10-01 起 A 的界是 **1.3**（原 16/9）。
enum BgCategory {
  /// A：比例 ≥ 1.3（规则 1 池）→ 宽构图，其中 ≥16:9 的部分真正固定不动
  ultraWide('A', '规则1·宽（≥1.3）'),

  /// B：1:1 ~ 1.3（横构图，规则 2 池）→ 宽铺满、随滚动
  landscape('B', '横构图（1:1 ~ 1.3）'),

  /// C：比 1:1 更窄（竖构图，规则 2 池）→ 宽铺满、随滚动，滚动幅度最大
  portrait('C', '竖构图（< 1:1）');

  const BgCategory(this.code, this.label);

  /// 单字母代号（清单里 `category` 的键）
  final String code;

  /// 中文标签
  final String label;

  /// 由尺寸判定分类（清单字段只作兜底展示，判定一律走这里）。
  static BgCategory of(int width, int height) {
    if (width <= 0 || height <= 0) return BgCategory.portrait;
    if (bgRuleOf(width, height) == BgFitRule.fillHeight) {
      return BgCategory.ultraWide;
    }
    return width >= height ? BgCategory.landscape : BgCategory.portrait;
  }

  /// 从清单里的 `category` 字段恢复；认不出按尺寸兜底。
  static BgCategory fromManifest(Object? raw, int width, int height) {
    final text = raw is String ? raw.trim().toUpperCase() : '';
    if (text.startsWith('A')) return BgCategory.ultraWide;
    if (text.startsWith('B')) return BgCategory.landscape;
    if (text.startsWith('C')) return BgCategory.portrait;
    return of(width, height);
  }
}

/// 图库中的一张背景图。
class BgImage {
  const BgImage({
    required this.id,
    required this.ref,
    required this.width,
    required this.height,
    this.bundled = true,
    this.srcWidth = 0,
    this.srcHeight = 0,
    this.bytes = 0,
    this.sourceName = '',
  });

  /// 唯一 id（内置 `bg_*` / 用户 `u_*`）
  final String id;

  /// 取用引用：内置是 asset key，用户是绝对文件路径
  final String ref;

  /// 是否内置（决定用 `Image.asset` 还是 `Image.file`）
  final bool bundled;

  /// 入库后的像素尺寸（**判定规则的唯一依据**）
  final int width;
  final int height;

  /// 原始尺寸与体积（仅登记表/设置页展示）
  final int srcWidth;
  final int srcHeight;
  final int bytes;

  /// 原文件名（设置页预览用）
  final String sourceName;

  /// 适配规则（现算，不信任清单字段）
  BgFitRule get rule => bgRuleOf(width, height);

  /// 是否随内容滚动
  bool get followsScroll => rule == BgFitRule.fillWidth;

  /// 几何分类
  BgCategory get category => BgCategory.of(width, height);

  /// 宽高比
  double get ratio => height <= 0 ? 0 : width / height;

  @override
  String toString() => 'BgImage($id ${width}x$height ${rule.name})';
}

/// 一个候选池（内置 + 用户合并后的视图）。
class BgLibrary {
  const BgLibrary(this.images);

  /// 空池（加载中/加载失败时的占位，渲染层据此退回纯色）
  static const BgLibrary empty = BgLibrary(<BgImage>[]);

  /// 全部候选（按 id 去重，内置在前）
  final List<BgImage> images;

  bool get isEmpty => images.isEmpty;
  bool get isNotEmpty => images.isNotEmpty;
  int get length => images.length;

  /// 规则 2 池（宽铺满、随滚动）：详细时间统计页与计时页优先用它。
  List<BgImage> get scrollablePool =>
      [for (final i in images) if (i.followsScroll) i];

  /// 规则 1 池（高铺满、背景固定）。
  List<BgImage> get fixedPool =>
      [for (final i in images) if (!i.followsScroll) i];

  /// 合并两个来源（内置 + 用户），按 id 去重、内置在前。
  static BgLibrary merge(BgLibrary a, BgLibrary b) {
    final seen = <String>{};
    final out = <BgImage>[];
    for (final image in [...a.images, ...b.images]) {
      if (seen.add(image.id)) out.add(image);
    }
    return BgLibrary(out);
  }

  /// 解析清单文本（内置/用户同一实现）。
  ///
  /// **容错偏向「能用就用」**：JSON 坏了整份作废（返回空池，渲染层退纯色）；
  /// 单条目缺字段/尺寸非法只丢这一条，不影响其余——与记忆日志
  /// 「坏行不拖垮整份文件」同一纪律。
  ///
  /// [refOf] 负责把「条目 + id」映射成取用引用：内置读条目里的 `asset`
  /// （缺省回退约定路径），用户拼本地绝对路径。
  static BgLibrary decode(
    String raw, {
    required bool bundled,
    required String Function(String id, Map<Object?, Object?> entry) refOf,
  }) {
    final Object? root;
    try {
      root = jsonDecode(raw);
    } on FormatException {
      return BgLibrary.empty;
    }
    if (root is! Map) return BgLibrary.empty;
    final list = root['images'];
    if (list is! List) return BgLibrary.empty;

    final out = <BgImage>[];
    final seen = <String>{};
    for (final entry in list) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! String || id.isEmpty) continue;
      final width = _intOf(entry['width']);
      final height = _intOf(entry['height']);
      if (width <= 0 || height <= 0) continue;
      if (!seen.add(id)) continue;
      out.add(BgImage(
        id: id,
        ref: refOf(id, entry),
        bundled: bundled,
        width: width,
        height: height,
        srcWidth: _intOf(entry['srcWidth']),
        srcHeight: _intOf(entry['srcHeight']),
        bytes: _intOf(entry['bytes']),
        sourceName: entry['source'] is String ? entry['source'] as String : '',
      ));
    }
    return BgLibrary(out);
  }

  /// 生成用户清单 JSON（导入后落盘用；内置清单由预处理脚本生成）。
  String encode() {
    final payload = <String, Object?>{
      'schema': kBgLibrarySchemaId,
      'images': [
        for (final i in images)
          <String, Object?>{
            'id': i.id,
            'width': i.width,
            'height': i.height,
            'srcWidth': i.srcWidth,
            'srcHeight': i.srcHeight,
            'bytes': i.bytes,
            'source': i.sourceName,
            'rule': i.rule == BgFitRule.fillHeight ? 1 : 2,
            'category': i.category.code,
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static int _intOf(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }
}
