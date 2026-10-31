/// 记忆日志文件的读写（platform 层：本项目唯一碰这个文件的地方）。
///
/// 设计取舍：
/// - **与备份同目录**（应用专属外存 `/sdcard/Android/data/<包名>/files`，
///   免存储权限、文件管理器可见）——跨程序联动的前提是外部程序够得着，
///   沿用 `mikufocus_backup.json` 已经验证过的通路，零新依赖零新权限；
/// - **原子写**：先写 `.tmp` 再 rename。日志会被外部程序同时读写，
///   半截文件比没文件更糟（解析全灭）；
/// - 读失败一律返回空文件而非抛异常：记忆是**增强项**，
///   它坏掉不能拖垮解读主链路（安静原则的延伸）。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/ai/memory_log.dart';

/// 记忆日志文件存放目录（外存优先，取不到回退应用文档目录）。
Future<Directory> aiMemoryLogDirectory() async {
  final dir = await getExternalStorageDirectory();
  return dir ?? await getApplicationDocumentsDirectory();
}

/// 记忆日志的磁盘读写。
class AiMemoryLogStore {
  AiMemoryLogStore({Future<Directory> Function()? directory})
      : _directory = directory ?? aiMemoryLogDirectory;

  /// 目录解析（测试注入临时目录；生产用 [aiMemoryLogDirectory]）
  final Future<Directory> Function() _directory;

  /// 日志文件句柄
  Future<File> file() async =>
      File(p.join((await _directory()).path, kMemoryLogFileName));

  /// 日志文件绝对路径（设置页展示给用户，供外部程序对接）
  Future<String> path() async => (await file()).path;

  /// 读取并解码；文件不存在或读失败返回空文件。
  Future<AiMemoryFile> read() async {
    final f = await file();
    if (!f.existsSync()) return const AiMemoryFile();
    try {
      return AiMemoryLog.decode(await f.readAsString());
    } on FileSystemException {
      return const AiMemoryFile();
    }
  }

  /// 覆盖写（原子：tmp + rename）。
  Future<void> write(AiMemoryFile data) async {
    final target = await file();
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(AiMemoryLog.encode(data), flush: true);
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      // 个别平台不支持覆盖式 rename：退化为先删后改名
      if (target.existsSync()) await target.delete();
      await tmp.rename(target.path);
    }
  }

  /// 读-改-写：把 [patch] 落到它 `date` 对应的条目上（字段级合并），
  /// 返回落盘后的该条目；写失败返回 null（调用方静默）。
  ///
  /// 「当日多次写、覆盖当日」的落地点：同一天永远是同一条，
  /// 被覆盖的只有应用拥有的字段，外部写入的键原样保留。
  Future<AiMemoryEntry?> upsert(AiMemoryEntry patch) async {
    try {
      final next = AiMemoryLog.upsert(await read(), patch);
      await write(next);
      for (final e in next.entries) {
        if (e.date == patch.date) return e;
      }
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// 删除日志文件（「删除 AI 数据」联动；外部程序随后的写入不受影响）。
  Future<void> clear() async {
    final f = await file();
    try {
      if (f.existsSync()) await f.delete();
    } on FileSystemException {
      // 删不掉不抛穿：这与「关闭 AI 功能」的成功与否无关
    }
  }
}
