/// 用户背景图库的磁盘读写（platform 层：本项目唯一碰这个目录的地方）。
///
/// 与内置图库（打进 APK 的 `assets/backgrounds/`）分开：
///
/// ```
/// <应用专属外存>/backgrounds/
///   ├── user_manifest.json               ← 用户图库清单（本类写）
///   └── u_<hash8>.webp                   ← 入库后的图（原生侧编码）
/// ```
///
/// 纪律与 `memory_log_store` 一致：
/// - **原子写**（tmp + rename）：清单被读写并发时，半截 JSON 比没有更糟；
/// - **读失败返回空池**：背景是装饰，坏了只能退纯色，不得拖垮页面。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/background/bg_image.dart';

/// 用户图库根目录（外存优先，取不到回退应用文档目录）。
Future<Directory> bgUserLibraryRoot() async {
  final dir = await getExternalStorageDirectory();
  return dir ?? await getApplicationDocumentsDirectory();
}

/// 用户背景图库的磁盘读写。
class BgLibraryStore {
  BgLibraryStore({Future<Directory> Function()? root})
      : _root = root ?? bgUserLibraryRoot;

  /// 外存根解析（测试注入临时目录；生产用 [bgUserLibraryRoot]）
  final Future<Directory> Function() _root;

  /// `backgrounds/` 目录
  Future<Directory> dir() async =>
      Directory(p.join((await _root()).path, kBgUserImageDirName));

  /// 用户清单文件
  Future<File> manifestFile() async =>
      File(p.join((await dir()).path, kBgUserManifestFileName));

  /// 清单绝对路径（设置页展示）
  Future<String> manifestPath() async => (await manifestFile()).path;

  /// 读取用户图库；目录/文件不存在或解析失败一律返回空池。
  Future<BgLibrary> read() async {
    final d = await dir();
    final file = File(p.join(d.path, kBgUserManifestFileName));
    if (!file.existsSync()) return BgLibrary.empty;
    try {
      return BgLibrary.decode(
        await file.readAsString(),
        bundled: false,
        refOf: (id, _) => p.join(d.path, '$id.webp'),
      );
    } on FileSystemException {
      return BgLibrary.empty;
    }
  }

  /// 覆盖写用户清单（原子：tmp + rename）。
  Future<void> write(BgLibrary library) async {
    final target = await manifestFile();
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(library.encode(), flush: true);
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      if (target.existsSync()) await target.delete();
      await tmp.rename(target.path);
    }
  }

  /// 从用户图库移除一张图：清单去条目 + 删除 `u_*.webp` 文件。
  ///
  /// 文件删不掉（占用/权限）不阻塞——清单里去掉条目后它就不再出现在
  /// 图库与候选池里；磁盘上多一个孤儿文件无害（下同 id 导入会复用）。
  Future<void> remove(String id) async {
    final current = await read();
    final kept =
        BgLibrary([for (final i in current.images) if (i.id != id) i]);
    await write(kept);
    try {
      final file = File(p.join((await dir()).path, '$id.webp'));
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // 清单已更新，文件残留无害
    }
  }
}
