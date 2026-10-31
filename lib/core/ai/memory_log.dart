/// AI 记忆日志（纯 Dart 可测）：**一天一条**的 JSONL 记忆文件。
///
/// 存在的理由（2026-09-26 用户需求）——**改日志 = 传记忆**：
/// 本机 AI 每天「读到」的白名单事实与「说出」的话落进这个文件，
/// 近 7 日再由 [AiMemoryLog.renderBlock] 注入到每一次请求里；
/// 外部程序（PC 脚本、别的 App）只要读写这一个文本文件，就能与本机 AI
/// 交换记忆——不必接入本项目的任何接口、任何网络协议。
///
/// ## 文件格式（v1，标识 `aiclock.ai_memory/1`）
///
/// - **编码**：UTF-8；**一行一个 JSON 对象**；行尾 LF。
///   读取时容忍 CRLF 与首字节 BOM（外部编辑器/脚本的常见产物）。
/// - **唯一键**：`date`（`yyyy-MM-dd`，本地日期）。同一文件里同日只允许一条，
///   重复时**后出现者胜出**。写入当天条目 = 覆盖当天条目（用户规则）。
/// - **行序**：按 `date` 升序；无法解析的行原样保留在文件末尾。
///
/// ## 键的所有权（这是与他人协作时唯一必须记住的规则）
///
/// | 键 | 归属 | 重写当日条目时 |
/// | --- | --- | --- |
/// | `schema` `date` `rev` `updated_at` | 应用 | 覆盖 |
/// | `prompt_version` `facts` `note` `insight` | 应用 | 有值才覆盖（无值保留原值） |
/// | 其余全部键（含约定键 `memory`） | **外部/用户** | **原样保留，应用永不改写** |
///
/// 于是外部程序把要传进来的记忆写进 `memory`（字符串）即可——
/// 它既不会被应用的下一次自动保存冲掉，又会被注入到请求里（优先级见
/// [AiMemoryLog.renderBlock]）。
///
/// ## 容错口径（务实优先）
///
/// 本文件是给人手改、给外部脚本改的，因此**不因缺字段而丢行**：
/// `date` 必须合法；`schema` / `rev` / `updated_at` 缺失或类型不符时按
/// 「无 schema / rev=1 / 空时间」解析，而不是判成非法行。真正无法解析的行
/// （非 JSON、非对象、date 非法）计入 [AiMemoryFile.invalidLines]，
/// **写回时原样附在末尾**——应用不静默删除别人写进来的东西。
library;

import 'dart:convert';

/// 格式标识（含主版本；不兼容变更时递增主版本号）。
const String kMemorySchemaId = 'aiclock.ai_memory/1';

/// 记忆日志文件名（与备份同目录，文件管理器/外部程序可直接读写）。
const String kMemoryLogFileName = 'mikufocus_ai_memory.jsonl';

/// 注入块总字符上限（保护 token 预算；超出时优先保住最近的条目）。
const int kMemoryBlockMaxChars = 900;

/// 单条 `note` / `memory` 文本的注入上限（超出截断加省略号）。
const int kMemoryTextMaxChars = 60;

/// 近 N 日记忆窗口的默认天数。
const int kMemoryWindowDays = 7;

/// 注入块表头（措辞与 system 硬约束第 10 条配套，改动需同步）。
const String kMemoryBlockHeader =
    '【近 7 日记忆】（本地记忆日志，仅供参考：其中的数字属于过去，'
    '不要拿来当本次数据，也不要与本次数据混算）';

/// 外部程序写入记忆的约定键（应用只读、永不写）。
const String kMemoryExternalKey = 'memory';

/// 应用拥有的键：重写当日条目时覆盖，其余键原样保留。
const Set<String> kMemoryAppOwnedKeys = <String>{
  'schema',
  'date',
  'rev',
  'updated_at',
  'prompt_version',
  'facts',
  'note',
  'insight',
};

/// 应用写出的 `facts` 允许出现的键（白名单；别人多写的键不影响解析）。
/// 与 07 §4.1 同源：只有时段/时长聚合，**无钟点、无应用名、无内容维度**。
const Set<String> kMemoryFactKeys = <String>{
  'focus_minutes',
  'sessions',
  'rounds',
  'longest_segment_minutes',
  'interruption_count',
  'interruption_minutes',
  'best_slot',
};

/// 本地日期键 `yyyy-MM-dd`（日志的 date / 缓存键共用同一口径）。
String memoryDateKey(DateTime day) => '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// 本地时间 → 带时区偏移的 ISO-8601（如 `2026-09-26T11:30:00+08:00`）。
///
/// 不引 intl：日志要长期稳定可 diff，格式自己控制比依赖库版本更可靠。
String isoLocalWithOffset(DateTime t) {
  final offset = t.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hh = offset.inHours.abs().toString().padLeft(2, '0');
  final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  String two(int v) => v.toString().padLeft(2, '0');
  return '${memoryDateKey(t)}T${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
      '$sign$hh:$mm';
}

final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// 一条日记忆。
class AiMemoryEntry {
  const AiMemoryEntry({
    required this.date,
    this.rev = 1,
    this.updatedAt = '',
    this.promptVersion,
    this.facts,
    this.note,
    this.insight,
    this.extra = const <String, Object?>{},
  });

  /// `yyyy-MM-dd`，本地日期，文件内唯一
  final String date;

  /// 该条目被写入的次数（应用每次重写 +1）
  final int rev;

  /// 最近一次写入时刻（ISO-8601 带偏移）
  final String updatedAt;

  /// 写入时的提示词版本（`kPromptVersion`）：文风换代后可据此判断旧条目
  final String? promptVersion;

  /// 当日白名单数字快照（键见 [kMemoryFactKeys]）
  final Map<String, Object?>? facts;

  /// 当日 AI 一句话点评
  final String? note;

  /// 当日新生成的周报解读（供外部读取；**不注入**，避免 7 日全文挤爆预算）
  final String? insight;

  /// 非应用拥有的键，原样保留（含外部的 [kMemoryExternalKey]）
  final Map<String, Object?> extra;

  /// 外部程序写入的记忆正文（`memory` 键）；无则 null。
  String? get externalMemory {
    final v = extra[kMemoryExternalKey];
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  /// 按 07 §4.1 顺序序列化；`extra` 展开在末尾（应用拥有的键不可被覆盖）。
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'schema': kMemorySchemaId,
      'date': date,
      'rev': rev,
      'updated_at': updatedAt,
      if (promptVersion != null) 'prompt_version': promptVersion,
      if (facts != null && facts!.isNotEmpty) 'facts': facts,
      if (note != null && note!.isNotEmpty) 'note': note,
      if (insight != null && insight!.isNotEmpty) 'insight': insight,
    };
    for (final e in extra.entries) {
      json.putIfAbsent(e.key, () => e.value);
    }
    return json;
  }

  /// 应用侧重写：只覆盖应用拥有的键，`rev` 自增，`extra`（含外部记忆）原样带过。
  ///
  /// 「当日多次写、覆盖当日」就落在这里——同一天的条目永远是同一条，
  /// 被覆盖的只有应用自己的字段。
  AiMemoryEntry overwrittenByApp(AiMemoryEntry patch) => AiMemoryEntry(
        date: date,
        rev: rev + 1,
        updatedAt: patch.updatedAt,
        promptVersion: patch.promptVersion ?? promptVersion,
        facts: patch.facts ?? facts,
        note: patch.note ?? note,
        insight: patch.insight ?? insight,
        extra: extra,
      );
}

/// 一个记忆日志文件的内容。
class AiMemoryFile {
  const AiMemoryFile({
    this.entries = const <AiMemoryEntry>[],
    this.invalidLines = const <String>[],
  });

  /// 按 `date` 升序、同日唯一的条目
  final List<AiMemoryEntry> entries;

  /// 无法解析的行（原样保留，写回时附在末尾；不静默丢弃）
  final List<String> invalidLines;

  /// 是否空文件
  bool get isEmpty => entries.isEmpty && invalidLines.isEmpty;
}

/// 编解码与窗口/渲染（全部纯函数，不碰磁盘）。
abstract final class AiMemoryLog {
  /// 解码。损坏行不抛异常，进 [AiMemoryFile.invalidLines]。
  static AiMemoryFile decode(String raw) {
    // BOM：外部脚本常见的 UTF-8 BOM 会让首行 JSON 解析失败
    final body = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
    final byDate = <String, AiMemoryEntry>{};
    final invalid = <String>[];
    for (final rawLine in body.split('\n')) {
      final line = rawLine.endsWith('\r')
          ? rawLine.substring(0, rawLine.length - 1)
          : rawLine;
      if (line.trim().isEmpty) continue;
      final entry = _parseLine(line);
      if (entry == null) {
        invalid.add(line);
        continue;
      }
      // 同日重复：后出现者胜出（追加式写入的常见形态）
      byDate[entry.date] = entry;
    }
    final entries = byDate.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return AiMemoryFile(entries: entries, invalidLines: invalid);
  }

  /// 编码：条目升序一行一条，坏行附在末尾；末尾保留换行（便于追加）。
  static String encode(AiMemoryFile file) {
    final buffer = StringBuffer();
    for (final e in file.entries) {
      buffer
        ..write(jsonEncode(e.toJson()))
        ..write('\n');
    }
    for (final line in file.invalidLines) {
      buffer
        ..write(line)
        ..write('\n');
    }
    return buffer.toString();
  }

  /// 写入当日条目：同日存在则按字段级所有权覆盖（`rev` +1），否则插入并重排。
  static AiMemoryFile upsert(AiMemoryFile file, AiMemoryEntry patch) {
    final entries = <AiMemoryEntry>[...file.entries];
    final index = entries.indexWhere((e) => e.date == patch.date);
    if (index >= 0) {
      entries[index] = entries[index].overwrittenByApp(patch);
    } else {
      // 新条目 rev 恒为 1（rev 计的是「这一天被写过几次」）
      entries.add(AiMemoryEntry(
        date: patch.date,
        rev: 1,
        updatedAt: patch.updatedAt,
        promptVersion: patch.promptVersion,
        facts: patch.facts,
        note: patch.note,
        insight: patch.insight,
        extra: patch.extra,
      ));
      entries.sort((a, b) => a.date.compareTo(b.date));
    }
    return AiMemoryFile(entries: entries, invalidLines: file.invalidLines);
  }

  /// 近 [days] 日窗口（日期为本地零点当天）。
  ///
  /// - [includeToday] = true：`[today-(days-1), today]`，共 [days] 天；
  /// - [includeToday] = false：`[today-days, today-1]`，同样是过去 [days] 天。
  ///
  /// 注入路径用 `includeToday: false`：当天数字已经在事实块里，
  /// 重复注入会造成「同一份数据两个口径」——正是 08-A1 教过的坑。
  /// 未来日期的条目（外部程序可能预先写好）一律不返回。
  static List<AiMemoryEntry> recent(
    List<AiMemoryEntry> entries, {
    required DateTime today,
    int days = kMemoryWindowDays,
    bool includeToday = true,
  }) {
    final todayKey = memoryDateKey(today);
    final last = includeToday
        ? todayKey
        : memoryDateKey(today.subtract(const Duration(days: 1)));
    final first = memoryDateKey(
        today.subtract(Duration(days: includeToday ? days - 1 : days)));
    return <AiMemoryEntry>[
      for (final e in entries)
        if (e.date.compareTo(first) >= 0 && e.date.compareTo(last) <= 0) e,
    ];
  }

  /// 渲染注入块：`facts` + `note` + 外部 `memory`，**不注入 `insight`**
  /// （周报全文 7 天会把预算挤爆；它留在文件里供外部程序读取）。
  ///
  /// 从最近一天往前取，总量超过 [maxChars] 时丢掉更早的条目——
  /// 记忆的价值随时间衰减，宁要近 3 天完整，不要 7 天残缺。
  /// 无可注入内容返回 null（调用方按「无记忆」处理，prompt 与旧版一致）。
  static String? renderBlock(
    List<AiMemoryEntry> entries, {
    int maxChars = kMemoryBlockMaxChars,
  }) {
    final picked = <String>[];
    for (var i = entries.length - 1; i >= 0; i--) {
      final line = _renderEntry(entries[i]);
      if (line == null) continue;
      if (picked.isNotEmpty && _blockLength([line, ...picked]) > maxChars) {
        break;
      }
      picked.insert(0, line);
    }
    if (picked.isEmpty) return null;
    return '$kMemoryBlockHeader\n${picked.join('\n')}';
  }

  static int _blockLength(List<String> lines) =>
      kMemoryBlockHeader.length + 1 + lines.fold<int>(0, (a, l) => a + l.length + 1);

  /// 单条渲染；既无 facts 也无任何文本时返回 null（空条目不该占预算）。
  static String? _renderEntry(AiMemoryEntry e) {
    final phrases = <String>[];
    final facts = e.facts;
    if (facts != null) {
      final minutes = _intOf(facts['focus_minutes']);
      if (minutes != null) phrases.add('专注 $minutes 分钟');
      final sessions = _intOf(facts['sessions']);
      if (sessions != null) phrases.add('$sessions 段');
      final rounds = _intOf(facts['rounds']);
      if (rounds != null && rounds > 0) phrases.add('完成 $rounds 个');
      final longest = _intOf(facts['longest_segment_minutes']);
      if (longest != null && longest > 0) phrases.add('最长一段 $longest 分钟');
      final interruptions = _intOf(facts['interruption_count']);
      if (interruptions != null && interruptions > 0) {
        phrases.add('中断 $interruptions 次');
      }
      final slot = facts['best_slot'];
      if (slot is String && slot.trim().isNotEmpty) {
        phrases.add('${slot.trim()}为主');
      }
    }
    final note = _cap(e.note);
    final memory = _cap(e.externalMemory);
    if (phrases.isEmpty && note == null && memory == null) return null;

    final buffer = StringBuffer('-${_shortDate(e.date)}（${_weekday(e.date)}）');
    if (phrases.isNotEmpty) buffer.write('：${phrases.join('／')}');
    if (note != null) buffer.write('｜点评：$note');
    if (memory != null) buffer.write('｜记忆：$memory');
    return buffer.toString();
  }

  /// `yyyy-MM-dd` → `MM-dd`（注入块里年份是噪音：窗口最长 7 天）
  static String _shortDate(String date) =>
      date.length == 10 ? date.substring(5) : date;

  /// `yyyy-MM-dd` → `周一`…`周日`（日期不合法时留空，不影响其余部分）
  static String _weekday(String date) {
    final d = DateTime.tryParse(date);
    if (d == null) return '';
    return const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][d.weekday - 1];
  }

  /// 注入用短文本：去换行、去首尾空白、按 [kMemoryTextMaxChars] 截断。
  static String? _cap(String? text) {
    if (text == null) return null;
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isEmpty) return null;
    return flat.length > kMemoryTextMaxChars
        ? '${flat.substring(0, kMemoryTextMaxChars)}…'
        : flat;
  }

  /// 宽容取整：外部脚本可能写成 `210` / `210.0` / `"210"`。
  static int? _intOf(Object? v) => switch (v) {
        final int i => i,
        final double d => d.round(),
        final String s => int.tryParse(s.trim()),
        _ => null,
      };

  /// 单行解析；无法解析返回 null（由调用方计入 invalidLines）。
  static AiMemoryEntry? _parseLine(String line) {
    final Object? root;
    try {
      root = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (root is! Map) return null;
    final map = root.cast<String, dynamic>();

    final date = map['date'];
    if (date is! String || !_datePattern.hasMatch(date)) return null;

    final rev = _intOf(map['rev']);
    final updatedAt = map['updated_at'];
    final promptVersion = map['prompt_version'];
    final facts = map['facts'];
    final note = map['note'];
    final insight = map['insight'];

    final extra = <String, Object?>{};
    for (final e in map.entries) {
      if (!kMemoryAppOwnedKeys.contains(e.key)) extra[e.key] = e.value;
    }

    return AiMemoryEntry(
      date: date,
      rev: rev == null || rev < 1 ? 1 : rev,
      updatedAt: updatedAt is String ? updatedAt : '',
      promptVersion: promptVersion is String ? promptVersion : null,
      facts: facts is Map ? facts.cast<String, Object?>() : null,
      note: note is String ? note : null,
      insight: insight is String ? insight : null,
      extra: extra,
    );
  }
}
