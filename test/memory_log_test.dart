/// 记忆日志格式层单测（看板 #54，纯 Dart 无 IO）。
///
/// 这是一份**给别人看的格式**（docs/09）：外部程序按它写、本机按它读，
/// 因此这里的断言就是规范的可执行版本。语义要点：
/// - 解码容错：BOM / CRLF / 缺字段都不丢行，真坏行进 invalidLines 而非抛异常；
/// - 同日唯一 + 后写胜出；写入按字段级合并，外部写的键原样保留；
/// - 近 7 日窗口含不含当日两种口径；未来日期的条目一律不进窗口；
/// - 注入块只含 facts / note / memory（insight 不注入），超预算时保最近的。
library;

import 'dart:convert';

import 'package:ai_clock/core/ai/memory_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一条合法行（外部程序视角的最小形态）。
String line({
  required String date,
  int? rev,
  String? updatedAt,
  Map<String, Object?>? facts,
  String? note,
  String? insight,
  Map<String, Object?> extra = const <String, Object?>{},
}) =>
    jsonEncode(<String, Object?>{
      'schema': kMemorySchemaId,
      'date': date,
      if (rev != null) 'rev': rev,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (facts != null) 'facts': facts,
      if (note != null) 'note': note,
      if (insight != null) 'insight': insight,
      ...extra,
    });

/// 应用侧写入用的补丁条目。
AiMemoryEntry patch(
  String date, {
  Map<String, Object?>? facts,
  String? note,
  String? insight,
}) =>
    AiMemoryEntry(
      date: date,
      updatedAt: '2026-09-26T20:00:00+08:00',
      promptVersion: 'v3',
      facts: facts,
      note: note,
      insight: insight,
    );

void main() {
  const day1 = '2026-09-20';
  const day2 = '2026-09-21';
  final today = DateTime(2026, 9, 26, 15, 30);

  group('dateKey / isoLocalWithOffset', () {
    test('本地日期键固定 yyyy-MM-dd', () {
      expect(memoryDateKey(DateTime(2026, 9, 6)), '2026-09-06');
      expect(memoryDateKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('ISO-8601 带时区偏移（外部程序据此判断写入时刻）', () {
      final s = isoLocalWithOffset(DateTime(2026, 9, 26, 9, 5, 3));
      expect(s, matches(RegExp(r'^2026-09-26T09:05:03[+-]\d{2}:\d{2}$')));
    });
  });

  group('decode 容错', () {
    test('多条按日期升序（输入乱序也拉正）', () {
      final file = AiMemoryLog.decode(<String>[
        line(date: day2),
        line(date: day1),
      ].join('\n'));
      expect(file.entries.map((e) => e.date), [day1, day2]);
      expect(file.invalidLines, isEmpty);
    });

    test('同日重复：后出现者胜出（追加式写入的常见形态）', () {
      final file = AiMemoryLog.decode(<String>[
        line(date: day1, note: '旧'),
        line(date: day1, note: '新'),
      ].join('\n'));
      expect(file.entries, hasLength(1));
      expect(file.entries.single.note, '新');
    });

    test('坏行进 invalidLines，好行照常解析（不整文件报废）', () {
      final file = AiMemoryLog.decode(<String>[
        'not json at all',
        line(date: day1),
        '{"date":"2026/09/20"}', // date 格式非法
        '[1,2,3]', // 不是对象
      ].join('\n'));
      expect(file.entries.single.date, day1);
      expect(file.invalidLines, hasLength(3));
    });

    test('BOM 与 CRLF 容忍（外部编辑器/Windows 脚本的产物）', () {
      final file = AiMemoryLog.decode(
          '\uFEFF${line(date: day1, note: 'x')}\r\n${line(date: day2)}\r\n');
      expect(file.entries, hasLength(2));
      expect(file.invalidLines, isEmpty);
    });

    test('缺 schema/rev/updated_at 不算坏行：容错为 rev=1、空时间', () {
      final file = AiMemoryLog.decode('{"date":"2026-09-20"}');
      expect(file.invalidLines, isEmpty);
      expect(file.entries.single.rev, 1);
      expect(file.entries.single.updatedAt, '');
    });

    test('空文件 / 纯空白', () {
      expect(AiMemoryLog.decode('').isEmpty, isTrue);
      expect(AiMemoryLog.decode('\n\n  \n').isEmpty, isTrue);
    });

    test('未知键进 extra（外部记忆就这么进来）', () {
      final file = AiMemoryLog.decode(
          line(date: day1, extra: {'memory': '上周在写论文', 'source': 'pc'}));
      final e = file.entries.single;
      expect(e.externalMemory, '上周在写论文');
      expect(e.extra['source'], 'pc');
    });
  });

  group('upsert 覆盖语义', () {
    test('新日期插入并保持升序，rev 恒为 1', () {
      final file = AiMemoryLog.upsert(
          AiMemoryLog.decode(line(date: day2)), patch(day1, note: 'a'));
      expect(file.entries.map((e) => e.date), [day1, day2]);
      expect(file.entries.first.rev, 1);
    });

    test('同日覆盖：rev+1、应用字段更新', () {
      final base = AiMemoryLog.decode(
          line(date: day1, rev: 3, facts: {'focus_minutes': 10}, note: '旧'));
      final file = AiMemoryLog.upsert(base, patch(day1, note: '新'));
      expect(file.entries.single.rev, 4);
      expect(file.entries.single.note, '新');
      // 未提供 facts → 保留原值（字段级别，不做整体替换）
      expect(file.entries.single.facts!['focus_minutes'], 10);
    });

    test('外部写的键永不被应用改写（跨程序记忆的关键承诺）', () {
      final base = AiMemoryLog.decode(
          line(date: day1, note: '旧', extra: {'memory': '外部记忆', 'tag': 'x'}));
      final file = AiMemoryLog.upsert(base, patch(day1, note: '新'));
      final e = file.entries.single;
      expect(e.note, '新');
      expect(e.externalMemory, '外部记忆');
      expect(e.extra['tag'], 'x');
    });

    test('upsert 不动 invalidLines（别人的坏行不因我写一次就消失）', () {
      final base = AiMemoryLog.decode('坏行\n${line(date: day1)}');
      final file = AiMemoryLog.upsert(base, patch(day2));
      expect(file.invalidLines, hasLength(1));
      expect(AiMemoryLog.encode(file).contains('坏行'), isTrue);
    });
  });

  group('encode / decode 往返', () {
    test('条目与坏行都能原样回来', () {
      final base = AiMemoryLog.decode(
          '坏行\n${line(date: day1, facts: {'focus_minutes': 95}, note: 'n', extra: {'memory': 'm'})}');
      final again = AiMemoryLog.decode(AiMemoryLog.encode(base));
      expect(again.entries.single.note, 'n');
      expect(again.entries.single.externalMemory, 'm');
      expect(again.invalidLines, ['坏行']);
    });

    test('编码一行一条、以 LF 收尾（便于外部程序追加）', () {
      final file = AiMemoryLog.upsert(
          const AiMemoryFile(), patch(day1, facts: {'focus_minutes': 1}));
      final text = AiMemoryLog.encode(file);
      expect(text.endsWith('\n'), isTrue);
      expect(text.trim().split('\n'), hasLength(1));
    });

    test('note 里的换行不会破坏「一行一条」', () {
      final file = AiMemoryLog.upsert(
          const AiMemoryFile(), patch(day1, note: '第一句\n第二句'));
      final text = AiMemoryLog.encode(file);
      expect(text.trim().split('\n'), hasLength(1));
      expect(AiMemoryLog.decode(text).entries.single.note, '第一句\n第二句');
    });
  });

  group('recent 近 N 日窗口', () {
    AiMemoryFile week() => AiMemoryLog.decode(<String>[
          for (var i = 0; i < 12; i++)
            line(date: memoryDateKey(today.subtract(Duration(days: i)))),
          line(date: memoryDateKey(today.add(const Duration(days: 2)))),
        ].join('\n'));

    test('含当日：今天往前共 7 天', () {
      final got = AiMemoryLog.recent(week().entries, today: today);
      expect(got, hasLength(7));
      expect(got.first.date, '2026-09-20');
      expect(got.last.date, '2026-09-26');
    });

    test('不含当日：今天-7 到今天-1，同样 7 天（注入路径用这个口径）', () {
      final got = AiMemoryLog.recent(week().entries,
          today: today, includeToday: false);
      expect(got, hasLength(7));
      expect(got.first.date, '2026-09-19');
      expect(got.last.date, '2026-09-25');
    });

    test('未来条目不进窗口（外部程序可能预先写好）', () {
      final got = AiMemoryLog.recent(week().entries, today: today);
      expect(got.any((e) => e.date == '2026-09-28'), isFalse);
    });

    test('窗口天数可调（预留接口）', () {
      final got =
          AiMemoryLog.recent(week().entries, today: today, days: 3);
      expect(got.map((e) => e.date), ['2026-09-24', '2026-09-25', '2026-09-26']);
    });
  });

  group('renderBlock 注入块', () {
    AiMemoryEntry entry(
      String date, {
      Map<String, Object?>? facts,
      String? note,
      String? insight,
      String? memory,
      int rev = 1,
    }) =>
        AiMemoryEntry(
          date: date,
          rev: rev,
          updatedAt: '2026-09-26T20:00:00+08:00',
          facts: facts,
          note: note,
          insight: insight,
          extra: memory == null
              ? const <String, Object?>{}
              : <String, Object?>{'memory': memory},
        );

    test('无可注入内容 → null（prompt 与未引入记忆时一致）', () {
      expect(AiMemoryLog.renderBlock(const []), isNull);
      expect(AiMemoryLog.renderBlock([entry(day1)]), isNull); // 空条目占位不算
    });

    test('facts + note + 外部 memory 三段都在，且带表头', () {
      final block = AiMemoryLog.renderBlock([
        entry(day1,
            facts: {'focus_minutes': 95, 'sessions': 3, 'interruption_count': 2},
            note: '下午最稳',
            memory: '这周在赶论文'),
      ])!;
      expect(block, startsWith(kMemoryBlockHeader));
      expect(block, contains('09-20（周日）'));
      expect(block, contains('专注 95 分钟'));
      expect(block, contains('3 段'));
      expect(block, contains('中断 2 次'));
      expect(block, contains('点评：下午最稳'));
      expect(block, contains('记忆：这周在赶论文'));
    });

    test('insight 不注入（周报全文留给外部程序读，不进 token 预算）', () {
      final block = AiMemoryLog.renderBlock(
          [entry(day1, facts: {'focus_minutes': 1}, insight: '一段很长的周报解读')]);
      expect(block, isNotNull);
      expect(block, isNot(contains('周报解读')));
    });

    test('零值不啰嗦：完成 0 个 / 中断 0 次 / 最长 0 分钟都不出现', () {
      final block = AiMemoryLog.renderBlock([
        entry(day1, facts: {
          'focus_minutes': 30,
          'sessions': 1,
          'rounds': 0,
          'interruption_count': 0,
          'longest_segment_minutes': 0,
        }),
      ])!;
      expect(block, contains('专注 30 分钟'));
      expect(block, isNot(contains('完成')));
      expect(block, isNot(contains('中断')));
      expect(block, isNot(contains('最长')));
    });

    test('单条文本截断到 kMemoryTextMaxChars', () {
      final long = '长' * 200;
      final block = AiMemoryLog.renderBlock([
        entry(day1, note: long),
      ])!;
      expect(block, contains('点评：${'长' * kMemoryTextMaxChars}…'));
      expect(block.contains('长' * (kMemoryTextMaxChars + 1)), isFalse);
    });

    test('文本里的换行被压平（一行一天，可 diff）', () {
      final block = AiMemoryLog.renderBlock([entry(day1, note: '上午\n下午')])!;
      expect(block, contains('点评：上午 下午'));
    });

    test('超预算丢最早的、保最近的，且至少保留最近一条', () {
      final entries = [
        for (var i = 6; i >= 0; i--)
          entry(memoryDateKey(today.subtract(Duration(days: i))),
              facts: {'focus_minutes': 100 + i}, note: '点' * 60),
      ];
      final block = AiMemoryLog.renderBlock(entries, maxChars: 200)!;
      final lines = block.split('\n').sublist(1);
      expect(lines.length, lessThan(entries.length));
      // 最近一天必须在，最早一天必须被丢掉
      expect(block, contains(memoryDateKey(today).substring(5)));
      expect(block, isNot(contains(memoryDateKey(today.subtract(const Duration(days: 6))).substring(5))));

      final tiny = AiMemoryLog.renderBlock(entries, maxChars: 10)!;
      expect(tiny.split('\n').sublist(1), hasLength(1)); // 至少一条
    });

    test('宽容数值：外部写成 double / 字符串也能渲染', () {
      final block = AiMemoryLog.renderBlock([
        entry(day1, facts: {'focus_minutes': 95.6, 'sessions': '3'}),
      ])!;
      expect(block, contains('专注 96 分钟'));
      expect(block, contains('3 段'));
    });
  });
}
