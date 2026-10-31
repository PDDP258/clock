/// 中断记录解析（US-D02，纯 Dart 可测）。
///
/// 中断 = 专注阶段内的暂停（番茄模式只记专注阶段；正计时所有暂停）。
/// 持久化形态：drift focus_session.pauses_json = [[startMillis, endMillis?], ...]，
/// endMillis 为 null 表示结算快照时刻仍在暂停中。
library;

import 'dart:convert';

/// 一次中断的墙钟区间（开始毫秒, 结束毫秒；null = 仍在暂停中）。
typedef Interruption = (int, int?);

/// 解析 pauses_json；老数据（null）与损坏数据一律回退空列表。
List<Interruption> parseInterruptions(String? pausesJson) {
  if (pausesJson == null || pausesJson.isEmpty) return const [];
  try {
    final decoded = jsonDecode(pausesJson);
    if (decoded is! List) return const [];
    return <Interruption>[
      for (final p in decoded)
        if (p is List && p.length == 2 && p[0] is num)
          ((p[0] as num).toInt(), (p[1] as num?)?.toInt()),
    ];
  } on FormatException {
    return const [];
  }
}

/// 解析 marks_json（正计时打点，US-B02 复盘）；返回「相对会话开始的偏移毫秒」
/// 升序列表。老数据（null）与损坏数据一律回退空列表。
List<int> parseMarks(String? marksJson) {
  if (marksJson == null || marksJson.isEmpty) return const [];
  try {
    final decoded = jsonDecode(marksJson);
    if (decoded is! List) return const [];
    return <int>[
      for (final m in decoded)
        if (m is num) m.toInt(),
    ]..sort();
  } on FormatException {
    return const [];
  }
}

/// 中断时刻的 hh:mm 展示（明细列表用）。
String formatInterruptionClock(int millis) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
