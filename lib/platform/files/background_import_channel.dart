/// 背景图入库的原生通道（platform 层）。
///
/// 为什么走原生而不是引插件：**入库要重编码**。Dart 只能编码 PNG，
/// 一张 2480×3508 的图转 PNG 是十几 MB，而目标是 WebP 几百 KB。
/// 原生 `BitmapFactory` + `Bitmap.compress` 是唯一能既快又小的路，
/// 且零新依赖（与既有 `aiclock/permissions` / `aiclock/audio` 同风格）。
///
/// 职责切分（**策略留 Dart，原生只当执行器**）：
/// - 原生 `pickImages` 只负责「选图（相册/文件管理器）+ 报出原始像素尺寸」，
///   目标尺寸由 Dart 用 [bgTargetSize] 算（与预处理脚本、判定规则同源，
///   可单测），再经 `processImages` 把 `outWidth/outHeight` 传下去；
/// - 原生照参数解码、缩放、压白底、编码 WebP，落到
///   `<外存>/backgrounds/u_<内容哈希8位>.webp`（哈希天然去重）。
///
/// 选图来源（2026-10-05 用户需求）：相册（`ACTION_PICK`，权限稳定、
/// 挑图顺手，**默认推荐**）与文件管理器（`ACTION_OPEN_DOCUMENT`，能进
/// 任意目录）。注意两者都**不能包 `createChooser`**——chooser 转发会让
/// 部分文件管理器返回的 URI 带不上读权限，探测直接失败（曾因此
/// 「选了图却提示未选择」，见看板 #61）。
library;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// 通道名（与 MainActivity 侧一致）。
const String kBgImportChannelName = 'aiclock/backgrounds';

/// 选图来源：相册 or 文件管理器。
enum BgPickSource {
  /// 系统相册（`ACTION_PICK`，推荐）
  gallery,

  /// 系统文件选择器（`ACTION_OPEN_DOCUMENT`）
  files;

  /// 原生侧的 wire 值。
  String get wire => this == BgPickSource.gallery ? 'gallery' : 'files';
}

/// 待入库的一张图（只到「探测出尺寸」为止）。
class BgImportCandidate {
  const BgImportCandidate({
    required this.uri,
    required this.name,
    required this.width,
    required this.height,
  });

  /// `content://` URI（选图只会有这一种来源）
  final String uri;

  /// 原文件名（仅展示与登记）
  final String name;

  /// 原始像素宽高（已按 EXIF 旋转修正）；0 表示探测失败（该条应直接跳过）
  final int width;
  final int height;

  /// 能否入库
  bool get usable => width > 0 && height > 0;

  Map<String, Object?> toMap() => <String, Object?>{
        'value': uri,
        'name': name,
        'width': width,
        'height': height,
      };

  static BgImportCandidate? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final value = raw['value'];
    if (value is! String || value.isEmpty) return null;
    return BgImportCandidate(
      uri: value,
      name: raw['name'] is String ? raw['name'] as String : '',
      width: _intOf(raw['width']),
      height: _intOf(raw['height']),
    );
  }

  static int _intOf(Object? raw) =>
      raw is int ? raw : (raw is num ? raw.toInt() : 0);
}

/// 一条入库指令（尺寸已由 Dart 按规则算好）。
class BgImportSpec {
  const BgImportSpec({
    required this.candidate,
    required this.outWidth,
    required this.outHeight,
  });

  final BgImportCandidate candidate;
  final int outWidth;
  final int outHeight;

  Map<String, Object?> toMap() => <String, Object?>{
        ...candidate.toMap(),
        'outWidth': outWidth,
        'outHeight': outHeight,
      };
}

/// 入库成功的一张图（原生已落盘）。
class BgImportedFile {
  const BgImportedFile({
    required this.path,
    required this.name,
    required this.width,
    required this.height,
    required this.bytes,
    this.srcWidth = 0,
    this.srcHeight = 0,
  });

  /// 落盘绝对路径（文件名即 id：`u_<hash8>.webp`）
  final String path;

  /// 原文件名
  final String name;

  /// 入库后尺寸（**判定规则的唯一依据**，已按 EXIF 旋转修正）
  final int width;
  final int height;

  final int bytes;

  /// 原始尺寸（EXIF 旋转前，仅登记/展示）
  final int srcWidth;
  final int srcHeight;

  /// 图库 id（取文件名去扩展名）
  String get id => p.basenameWithoutExtension(path);

  static BgImportedFile? fromMap(Object? raw) {
    if (raw is! Map) return null;
    if (raw['ok'] != true) return null;
    final path = raw['path'];
    if (path is! String || path.isEmpty) return null;
    return BgImportedFile(
      path: path,
      name: raw['name'] is String ? raw['name'] as String : '',
      width: BgImportCandidate._intOf(raw['width']),
      height: BgImportCandidate._intOf(raw['height']),
      bytes: BgImportCandidate._intOf(raw['bytes']),
      srcWidth: BgImportCandidate._intOf(raw['srcWidth']),
      srcHeight: BgImportCandidate._intOf(raw['srcHeight']),
    );
  }
}

/// 原生通道的 Dart 包装。所有方法在原生不可用时（单测/桌面）
/// **静默返回空列表**——背景是装饰，不该因为插件缺失就让设置页报错。
class BgImportChannel {
  const BgImportChannel();

  static const MethodChannel _channel = MethodChannel(kBgImportChannelName);

  /// 打开选图（多选），[source] 决定相册还是文件管理器。
  /// 返回候选列表（含原始尺寸）；探测失败的那条 width/height 为 0，
  /// 上层据此区分「没选」和「选了但读不出来」。
  Future<List<BgImportCandidate>> pick({required BgPickSource source}) async {
    final raw = await _invoke<List<Object?>>('pickImages', <String, Object?>{
      'source': source.wire,
    });
    return _candidates(raw);
  }

  /// 按 [specs] 解码→缩放→压白底→编码 WebP→落盘。
  Future<List<BgImportedFile>> process(List<BgImportSpec> specs) async {
    if (specs.isEmpty) return const <BgImportedFile>[];
    final raw = await _invoke<List<Object?>>('processImages', <String, Object?>{
      'items': [for (final s in specs) s.toMap()],
    });
    if (raw == null) return const <BgImportedFile>[];
    return <BgImportedFile>[
      for (final e in raw)
        if (BgImportedFile.fromMap(e) case final f?) f,
    ];
  }

  Future<T?> _invoke<T>(String method, Object? args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null; // 单测/桌面：没有原生实现
    } on PlatformException {
      return null; // 选图被取消等：静默
    }
  }

  static List<BgImportCandidate> _candidates(List<Object?>? raw) {
    if (raw == null) return const <BgImportCandidate>[];
    return <BgImportCandidate>[
      for (final e in raw)
        if (BgImportCandidate.fromMap(e) case final c?) c,
    ];
  }
}
