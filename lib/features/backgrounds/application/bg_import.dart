/// 背景图导入（application 层）：把「用户挑的图」变成「图库里的条目」。
///
/// 链路（策略在 Dart，脏活在原生）：
/// ```
/// 选图（相册/文件管理器） → 候选(含原始尺寸) → bgTargetSize 算目标
///        → 原生编码落盘 → 生成 BgImage → 合并进用户清单 → 原子写 → 失效候选池
/// ```
///
/// 失败口径：**导入失败不弹错误页，只回报数字**。背景是装饰，
/// 一张图坏了不该打断设置页的操作流。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/background/bg_fit.dart';
import '../../../core/background/bg_image.dart';
import '../../../platform/files/background_import_channel.dart';
import 'background_controller.dart';

/// 一次导入的结果。
class BgImportOutcome {
  const BgImportOutcome({
    required this.picked,
    required this.added,
    required this.duplicate,
    required this.failed,
  });

  /// 空结果（没选到图 / 原生不可用）
  static const BgImportOutcome none =
      BgImportOutcome(picked: 0, added: 0, duplicate: 0, failed: 0);

  /// 探测到的候选数
  final int picked;

  /// 新入库张数
  final int added;

  /// 内容哈希命中、复用已有文件的张数
  final int duplicate;

  /// 失败张数
  final int failed;

  bool get isEmpty => picked == 0 && failed == 0;

  /// 一句话结果（设置页 SnackBar 用）。
  String get message => switch ((picked, added, duplicate, failed)) {
        (0, _, _, 0) => '没有选到图片',
        (0, _, _, _) => '这 $failed 张读不出来（换一张试试）',
        (_, 0, 0, _) => '导入失败：这 $failed 张处理不了（换一张试试）',
        (_, _, _, 0) =>
          '已添加 $added 张${duplicate > 0 ? '（$duplicate 张已存在）' : ''}',
        _ => '已添加 $added 张，$duplicate 张已存在，$failed 张失败',
      };
}

/// 把原生落盘结果转成图库条目（纯函数，可单测）。
///
/// id 取文件名（`u_<hash8>`），ref 是绝对路径——与内置条目的 asset key
/// 区分开；`bundled: false` 决定渲染层走 `Image.file`。
List<BgImage> bgImagesFromImport(List<BgImportedFile> files) => [
      for (final f in files)
        BgImage(
          id: f.id,
          ref: f.path,
          bundled: false,
          width: f.width,
          height: f.height,
          srcWidth: f.srcWidth,
          srcHeight: f.srcHeight,
          bytes: f.bytes,
          sourceName: f.name,
        ),
    ];

/// 按 [candidates] 生成入库指令（目标尺寸由 [bgTargetSize] 算，
/// 与预处理脚本同源——app 内导入的图和随包预处理的图同一套口径）。
List<BgImportSpec> bgImportSpecsOf(List<BgImportCandidate> candidates) => [
      for (final c in candidates)
        if (c.usable)
          BgImportSpec(
            candidate: c,
            outWidth: bgTargetSize(c.width, c.height).width,
            outHeight: bgTargetSize(c.width, c.height).height,
          ),
    ];

/// 导入服务（依赖全部来自 provider，单测可整体替换）。
final bgImportServiceProvider =
    Provider<BgImportService>((ref) => BgImportService(ref));

/// 用户图库（设置页统计「内置 N · 用户 M」用）。
final bgUserLibraryProvider = FutureProvider<BgLibrary>(
    (ref) => ref.watch(bgLibraryStoreProvider).read());

/// 导入服务。
class BgImportService {
  const BgImportService(this._ref);

  final Ref _ref;

  /// 走系统相册（多选）——权限稳定、挑图顺手，**默认入口**。
  Future<BgImportOutcome> fromGallery() => _runOf(BgPickSource.gallery);

  /// 走系统文件管理器（多选）——能进任意目录，相册找不到时的备选。
  Future<BgImportOutcome> fromFileManager() => _runOf(BgPickSource.files);

  Future<BgImportOutcome> _runOf(BgPickSource source) async {
    final candidates =
        await _ref.read(bgImportChannelProvider).pick(source: source);
    return _run(candidates);
  }

  Future<BgImportOutcome> _run(List<BgImportCandidate> candidates) async {
    final usable = [for (final c in candidates) if (c.usable) c];
    final unusable = candidates.length - usable.length;
    if (usable.isEmpty) {
      return BgImportOutcome(
          picked: 0, added: 0, duplicate: 0, failed: unusable);
    }
    final imported =
        await _ref.read(bgImportChannelProvider).process(bgImportSpecsOf(usable));
    final failed = usable.length - imported.length + unusable;
    if (imported.isEmpty) {
      return BgImportOutcome(
          picked: usable.length, added: 0, duplicate: 0, failed: failed);
    }

    final current = await _ref.read(bgLibraryStoreProvider).read();
    final known = <String>{for (final i in current.images) i.id};
    final fresh = bgImagesFromImport(imported);
    final added = [for (final i in fresh) if (!known.contains(i.id)) i].length;
    final duplicate = fresh.length - added;

    // 已有条目在前、新条目在后：merge 按 id 去重，重复导入不会让
    // 条目顺序跳动（顺序影响「下一张抽到谁」的观感）
    await _ref
        .read(bgLibraryStoreProvider)
        .write(BgLibrary.merge(current, BgLibrary(fresh)));
    _ref.invalidate(bgLibraryProvider);

    return BgImportOutcome(
      picked: usable.length,
      added: added,
      duplicate: duplicate,
      failed: failed,
    );
  }
}
