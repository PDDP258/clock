/// 数据导出与备份（看板 #45）：drift 全量专注记录 ↔ 应用专属外存 JSON 文件。
///
/// 设计取舍：
/// - 固定路径（应用专属外存目录，Android 10+ 免权限），不引 file_picker/
///   share_plus——M500 场景用户用文件管理器自取/自放，零新依赖零新权限；
/// - 导入 = 全量替换（先自动留存当前数据到 *_pre_import.json 再清空插入），
///   不做合并——合并的主键/去重语义复杂且收益低；
/// - 编解码与校验在 core/backup/backup_codec.dart（纯 Dart 已单测）。
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/backup/backup_codec.dart';
import '../../../platform/db/app_database.dart';

/// 备份文件所在目录：应用专属外存（/sdcard/Android/data/<包名>/files），
/// 免存储权限且文件管理器可见；取不到外存时回退应用文档目录。
Future<Directory> backupDirectory() async {
  final dir = await getExternalStorageDirectory();
  return dir ?? await getApplicationDocumentsDirectory();
}

/// 导出全部专注记录到备份文件。返回 (文件路径, 记录条数)。
Future<(String, int)> exportSessionsBackup(AppDatabase db) async {
  final rows = await db.focusSessionDao.allSessions();
  final data = BackupData(
    exportedAtMillis: DateTime.now().millisecondsSinceEpoch,
    sessions: [for (final r in rows) _toBackup(r)],
  );
  final file = File(p.join((await backupDirectory()).path,
      BackupCodec.backupFileName));
  await file.writeAsString(BackupCodec.encode(data));
  return (file.path, rows.length);
}

/// 从备份文件导入（全量替换）。返回导入条数。
/// 抛 [FormatException]（文件缺失/损坏/不兼容，message 可直接展示）。
Future<int> importSessionsBackup(AppDatabase db) async {
  final dir = await backupDirectory();
  final file = File(p.join(dir.path, BackupCodec.backupFileName));
  if (!file.existsSync()) {
    throw FormatException(
        '未找到备份文件：${file.path}\n请先把备份文件放到该目录');
  }
  final data = BackupCodec.decode(await file.readAsString());

  // 导入前自动留存当前数据（防误操作：替换式导入不可逆）
  await exportSessionsBackupTo(db, dir, BackupCodec.preImportFileName);

  final dao = db.focusSessionDao;
  await dao.deleteAllSessions();
  for (final s in data.sessions) {
    await dao.insertSession(_toCompanion(s));
  }
  return data.sessions.length;
}

/// 导出到指定目录的指定文件名（导入前自动留存用）。
Future<void> exportSessionsBackupTo(
    AppDatabase db, Directory dir, String fileName) async {
  final rows = await db.focusSessionDao.allSessions();
  final data = BackupData(
    exportedAtMillis: DateTime.now().millisecondsSinceEpoch,
    sessions: [for (final r in rows) _toBackup(r)],
  );
  await File(p.join(dir.path, fileName))
      .writeAsString(BackupCodec.encode(data));
}

BackupSession _toBackup(FocusSession r) => BackupSession(
      startAt: r.startAt,
      endAt: r.endAt,
      plannedFocusMillis: r.plannedFocusMillis,
      actualFocusMillis: r.actualFocusMillis,
      rounds: r.rounds,
      completed: r.completed,
      mode: r.mode,
      marksJson: r.marksJson,
      intervalsJson: r.intervalsJson,
      pausesJson: r.pausesJson,
      tag: r.tag,
    );

/// 备份 → drift companion。不带 id：重新自增，避免与存量主键冲突。
FocusSessionsCompanion _toCompanion(BackupSession s) => FocusSessionsCompanion(
      startAt: Value(s.startAt),
      endAt: Value(s.endAt),
      plannedFocusMillis: Value(s.plannedFocusMillis),
      actualFocusMillis: Value(s.actualFocusMillis),
      rounds: Value(s.rounds),
      completed: Value(s.completed),
      mode: Value(s.mode),
      marksJson: Value(s.marksJson),
      intervalsJson: Value(s.intervalsJson),
      pausesJson: Value(s.pausesJson),
      tag: Value(s.tag),
    );
