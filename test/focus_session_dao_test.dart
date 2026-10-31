/// FocusSessionDao 去重 / 行身份解析回归用例（R11 统计翻倍修复）。
///
/// 背景：中断后重开番茄会产生「同 startAt、不同计入」的多行，旧实现下
/// 每次重启都可能再插一行 → 统计翻倍、一天超 24 小时。修复后必须在
/// 写入侧按 startAt 解析行身份、读侧按 (startAt, mode) 去重，保证
/// **任何时刻只记一次**。
library;

import 'package:ai_clock/platform/db/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一条番茄会话落库记录。
FocusSessionsCompanion _entry({
  required int startAt,
  required int actualFocusMillis,
  int plannedFocusMillis = 1500000,
  int? endAt,
  String mode = 'pomodoro',
  int rounds = 0,
  bool completed = false,
}) {
  return FocusSessionsCompanion.insert(
    startAt: startAt,
    plannedFocusMillis: plannedFocusMillis,
    actualFocusMillis: actualFocusMillis,
    endAt: Value(endAt),
    mode: Value(mode),
    rounds: Value(rounds),
    completed: Value(completed),
  );
}

void main() {
  late AppDatabase db;
  late FocusSessionDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = db.focusSessionDao;
  });

  tearDown(() async => db.close());

  group('settleSession 行身份解析（id 丢失不双插）', () {
    test('sessionId 为空时按 startAt 找回同一行，不产生重复行', () async {
      final id1 = await dao.settleSession(
        _entry(startAt: 1000, actualFocusMillis: 600000),
      );

      // 模拟「结算后立即被杀」：prefs 里的行 id 丢失，只剩 startAt
      final id2 = await dao.settleSession(
        _entry(startAt: 1000, actualFocusMillis: 900000),
      );

      expect(id2, id1); // 命中同一行
      final all = await dao.allSessions();
      expect(all.length, 1); // 没有第二条
      expect(all.single.actualFocusMillis, 900000); // 后写覆盖
    });

    test('传入正确 sessionId 时持续更新同一行', () async {
      final id = await dao.settleSession(
        _entry(startAt: 2000, actualFocusMillis: 100),
      );
      await dao.settleSession(
        _entry(startAt: 2000, actualFocusMillis: 5000),
        sessionId: id,
      );

      final all = await dao.allSessions();
      expect(all.length, 1);
      expect(all.single.id, id);
      expect(all.single.actualFocusMillis, 5000);
    });

    test('不同 startAt 是不同会话，各自成行', () async {
      await dao.settleSession(_entry(startAt: 1000, actualFocusMillis: 100));
      await dao.settleSession(_entry(startAt: 5000, actualFocusMillis: 200));

      expect((await dao.allSessions()).length, 2);
    });
  });

  group('settleSession 高水位保证（R13：已确认数据永不回缩）', () {
    test('更小的 actual 不覆盖既有整行（终止/重开竞态回归）', () async {
      final id = await dao.settleSession(
        _entry(startAt: 1000, actualFocusMillis: 1200000), // 20 分钟已确认
      );
      // 异常路径：同一行带着「几秒」的更小值再来一次
      final id2 = await dao.settleSession(
        _entry(startAt: 1000, actualFocusMillis: 3000),
        sessionId: id,
      );

      expect(id2, id);
      final all = await dao.allSessions();
      expect(all.length, 1);
      expect(all.single.actualFocusMillis, 1200000); // 保留 20 分钟
    });

    test('无 id 时按 startAt 命中的更小写入同样不回缩', () async {
      await dao.settleSession(_entry(startAt: 7000, actualFocusMillis: 900000));
      await dao.settleSession(_entry(startAt: 7000, actualFocusMillis: 5000));

      final all = await dao.allSessions();
      expect(all.length, 1);
      expect(all.single.actualFocusMillis, 900000);
    });

    test('实际专注超过墙钟跨度的异常增大被截断到跨度内', () async {
      final id = await dao.settleSession(
        _entry(startAt: 1000, actualFocusMillis: 300000, endAt: 301000),
      );
      // startAt=1000, endAt=301000 → 跨度 300000ms；谎报 10 分钟
      await dao.settleSession(
        _entry(
          startAt: 1000,
          actualFocusMillis: 600000,
          endAt: 301000,
        ),
        sessionId: id,
      );

      final row = await dao.sessionByStartAt(1000);
      expect(row!.actualFocusMillis, 300000);
    });
  });

  group('sessionByStartAt 行选择', () {
    test('同 startAt 取 actualFocusMillis 最大的一行', () async {
      await dao.insertSession(_entry(startAt: 1000, actualFocusMillis: 300));
      await dao.insertSession(_entry(startAt: 1000, actualFocusMillis: 900));

      final row = await dao.sessionByStartAt(1000);
      expect(row!.actualFocusMillis, 900);
    });

    test('无匹配返回 null', () async {
      expect(await dao.sessionByStartAt(999), isNull);
    });
  });

  group('读侧去重（任何时刻只记一次）', () {
    test('同 startAt 多行累计只取最大一条（历史脏数据兜底）', () async {
      // 模拟「中断后另开同 startAt 的多段番茄」
      await dao.insertSession(_entry(startAt: 1000, actualFocusMillis: 600000));
      await dao.insertSession(_entry(startAt: 1000, actualFocusMillis: 700000));
      await dao.insertSession(_entry(startAt: 1000, actualFocusMillis: 900000));

      final day = await dao.sessionsOfDay(0, 10000);
      expect(day.length, 1);
      expect(day.single.actualFocusMillis, 900000);

      expect(await dao.totalFocusMillisOfDay(0, 10000), 900000);
    });

    test('同 startAt 不同 mode 视为两个会话，各自保留', () async {
      await dao.insertSession(
          _entry(startAt: 1000, actualFocusMillis: 100, mode: 'pomodoro'));
      await dao.insertSession(
          _entry(startAt: 1000, actualFocusMillis: 200, mode: 'countUp'));

      final day = await dao.sessionsOfDay(0, 10000);
      expect(day.length, 2);
      expect(await dao.totalFocusMillisOfDay(0, 10000), 300);
    });

    test('dailyFocusMillisOfRange 分桶前同样去重', () async {
      await dao.insertSession(_entry(startAt: 1000, actualFocusMillis: 60000));
      await dao.insertSession(_entry(startAt: 1000, actualFocusMillis: 120000));

      final buckets = await dao.dailyFocusMillisOfRange(0, 10000);
      expect(buckets.values.fold<int>(0, (a, b) => a + b), 120000);
    });
  });

  group('dedupeByStartAt 纯函数', () {
    test('每组 (startAt, mode) 只留 actualFocusMillis 最大，按 startAt 排序', () {
      FocusSession row(int id, int startAt, int actual, [String mode = 'p']) =>
          FocusSession(
            id: id,
            startAt: startAt,
            plannedFocusMillis: 1000,
            actualFocusMillis: actual,
            rounds: 0,
            completed: false,
            mode: mode,
          );

      final out = FocusSessionDao.dedupeByStartAt([
        row(1, 5000, 100),
        row(2, 1000, 50),
        row(3, 1000, 80),
        row(4, 1000, 80, 'countUp'),
      ]);

      expect(out.map((r) => r.id).toList(), [3, 4, 1]);
    });
  });

  group('deleteDuplicateSessions 启动自愈', () {
    test('同 startAt 只留 actual 最大；keepId 强制保留活跃行', () async {
      final active = await dao.insertSession(
          _entry(startAt: 1000, actualFocusMillis: 600000));
      await dao.insertSession(_entry(startAt: 1000, actualFocusMillis: 900000));

      final deleted = await dao.deleteDuplicateSessions(keepId: active);

      expect(deleted, 1);
      final all = await dao.allSessions();
      expect(all.length, 1);
      expect(all.single.id, active); // 活跃行优先于更大值
      expect(all.single.actualFocusMillis, 600000);
    });

    test('无 keepId 时保留 actual 最大行', () async {
      await dao.insertSession(_entry(startAt: 1000, actualFocusMillis: 600000));
      await dao.insertSession(_entry(startAt: 1000, actualFocusMillis: 900000));

      await dao.deleteDuplicateSessions();

      final all = await dao.allSessions();
      expect(all.single.actualFocusMillis, 900000);
    });
  });
}
