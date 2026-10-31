/// 备份编解码（纯 Dart，可单测）：专注记录 ↔ JSON 文本。
///
/// 设计要点（看板 #45 数据导出与备份）：
/// - 格式带 app 标记与版本号，导入时严格校验，损坏/不兼容给中文原因；
/// - 只导业务字段，不导自增 id（导入后重新分配，避免与存量主键冲突）；
/// - 分层：本文件不依赖 drift 行类型，platform↔本模型的映射在
///   features/settings/application/data_backup.dart。
library;

import 'dart:convert';

/// 一条专注记录的备份形态（与 drift focus_session 列一一对应，无 id）。
class BackupSession {
  const BackupSession({
    required this.startAt,
    required this.endAt,
    required this.plannedFocusMillis,
    required this.actualFocusMillis,
    required this.rounds,
    required this.completed,
    required this.mode,
    required this.marksJson,
    required this.intervalsJson,
    required this.pausesJson,
    required this.tag,
  });

  final int startAt;
  final int? endAt;
  final int plannedFocusMillis;
  final int actualFocusMillis;
  final int rounds;
  final bool completed;
  final String mode;
  final String? marksJson;
  final String? intervalsJson;
  final String? pausesJson;
  final String? tag;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'start_at': startAt,
        'end_at': endAt,
        'planned_focus_millis': plannedFocusMillis,
        'actual_focus_millis': actualFocusMillis,
        'rounds': rounds,
        'completed': completed,
        'mode': mode,
        'marks_json': marksJson,
        'intervals_json': intervalsJson,
        'pauses_json': pausesJson,
        'tag': tag,
      };
}

/// 备份文件内容。
class BackupData {
  const BackupData({required this.exportedAtMillis, required this.sessions});

  /// 导出时刻（毫秒时间戳）
  final int exportedAtMillis;

  /// 全部专注记录（按 startAt 升序）
  final List<BackupSession> sessions;
}

/// 备份文件的编码/解码与校验。
abstract final class BackupCodec {
  /// 当前备份格式版本（结构变更时 +1，导入拒绝更高版本）
  static const currentVersion = 1;

  /// 默认备份文件名（应用专属外存目录下，用户可用文件管理器取走）
  static const backupFileName = 'mikufocus_backup.json';

  /// 导入前自动留存当前数据的文件名（防误操作覆盖唯一备份）
  static const preImportFileName = 'mikufocus_backup_pre_import.json';

  /// 编码为备份 JSON 文本（带缩进，便于人工查看核对）。
  static String encode(BackupData data) {
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'app': 'MikuFocus',
      'version': currentVersion,
      'exported_at': data.exportedAtMillis,
      'session_count': data.sessions.length,
      'sessions': [for (final s in data.sessions) s.toJson()],
    });
  }

  /// 解码并校验。一切不合法都抛 [FormatException]（中文原因，UI 直接展示）。
  static BackupData decode(String raw) {
    final Object? root;
    try {
      root = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('不是合法的 JSON 文件');
    }
    if (root is! Map) throw const FormatException('备份文件结构不正确');
    final map = root.cast<String, dynamic>();
    if (map['app'] != 'MikuFocus') {
      throw const FormatException('这不是 MikuFocus 的备份文件');
    }
    final version = map['version'];
    if (version is! int || version > currentVersion) {
      throw const FormatException('备份版本不兼容（文件来自更新的版本）');
    }
    final exportedAt = map['exported_at'];
    if (exportedAt is! int) {
      throw const FormatException('备份文件缺少导出时间');
    }
    final list = map['sessions'];
    if (list is! List) throw const FormatException('备份文件缺少记录列表');

    final sessions = <BackupSession>[];
    for (var i = 0; i < list.length; i++) {
      sessions.add(_decodeSession(list[i], i));
    }
    sessions.sort((a, b) => a.startAt.compareTo(b.startAt));
    return BackupData(exportedAtMillis: exportedAt, sessions: sessions);
  }

  static BackupSession _decodeSession(Object? item, int index) {
    FormatException bad() =>
        FormatException('第 ${index + 1} 条记录字段缺失或类型错误');
    if (item is! Map) throw bad();
    final m = item.cast<String, dynamic>();
    final startAt = m['start_at'];
    final planned = m['planned_focus_millis'];
    final actual = m['actual_focus_millis'];
    final rounds = m['rounds'];
    final completed = m['completed'];
    final mode = m['mode'];
    if (startAt is! int ||
        planned is! int ||
        actual is! int ||
        rounds is! int ||
        completed is! bool ||
        mode is! String) {
      throw bad();
    }
    final endAt = m['end_at'];
    if (endAt != null && endAt is! int) throw bad();
    String? opt(String key) {
      final v = m[key];
      if (v != null && v is! String) throw bad();
      return v as String?;
    }

    return BackupSession(
      startAt: startAt,
      endAt: endAt as int?,
      plannedFocusMillis: planned,
      actualFocusMillis: actual,
      rounds: rounds,
      completed: completed,
      mode: mode,
      marksJson: opt('marks_json'),
      intervalsJson: opt('intervals_json'),
      pausesJson: opt('pauses_json'),
      tag: opt('tag'),
    );
  }
}
