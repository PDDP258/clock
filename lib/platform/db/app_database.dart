/// drift 本地数据库（SQLite）。
///
/// ⚠️ 本文件依赖 build_runner 生成的 `app_database.g.dart`：
/// 首次拉取代码或修改表结构后，必须执行
///   dart run build_runner build --delete-conflicting-outputs
/// 否则无法编译。
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// ---------------------------------------------------------------- 表定义

/// 专注记录：每次番茄会话（开始→结束）落一行。
class FocusSessions extends Table {
  @override
  String get tableName => 'focus_session';

  IntColumn get id => integer().autoIncrement()();

  /// 会话开始时间（毫秒时间戳）
  IntColumn get startAt => integer()();

  /// 会话结束时间；进行中为 null
  IntColumn get endAt => integer().nullable()();

  /// 计划专注总毫秒
  IntColumn get plannedFocusMillis => integer()();

  /// 实际专注总毫秒（扣除暂停/休息）
  IntColumn get actualFocusMillis => integer()();

  /// 完成轮数
  IntColumn get rounds => integer().withDefault(const Constant(0))();

  /// 是否正常完成（false = 提前结束）
  BoolColumn get completed => boolean().withDefault(const Constant(false))();

  /// 计时模式：pomodoro / countUp（schema v2 新增）
  TextColumn get mode => text().withDefault(const Constant('pomodoro'))();

  /// 正计时打点偏移毫秒列表（JSON 数组，schema v3 新增；番茄模式为 null）
  TextColumn get marksJson => text().nullable()();

  /// 各专注段的实际墙钟区间（JSON 数组 [[start,end],...]，schema v4 新增；
  /// 供时间轴「断断续续 + 休息空隙」渲染；老数据为 null 时回退整段渲染）
  TextColumn get intervalsJson => text().nullable()();

  /// 专注阶段内的暂停（中断）区间（JSON 数组 [[start,end],...]，end 可空
  /// 表示暂停中；schema v5 新增，US-D02）
  TextColumn get pausesJson => text().nullable()();

  /// 会话关联的任务/标签（schema v5 新增，US-B05；无标签为 null）
  TextColumn get tag => text().nullable()();
}

/// 每日各应用使用时长（usage_stats 采集结果落库）。
class UsageStatDailies extends Table {
  @override
  String get tableName => 'usage_stat_daily';

  IntColumn get id => integer().autoIncrement()();

  /// 日期，格式 yyyy-MM-dd
  TextColumn get day => text()();

  /// 应用包名
  TextColumn get packageName => text()();

  /// 当日前台总毫秒
  IntColumn get foregroundMillis => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {day, packageName},
      ];
}

/// 应用规则 / 白名单（V0.3 应用拦截预留）。
class AppRules extends Table {
  @override
  String get tableName => 'app_rule';

  IntColumn get id => integer().autoIncrement()();

  /// 应用包名
  TextColumn get packageName => text().unique()();

  /// 规则类型：whitelist / blacklist / limit
  TextColumn get ruleType => text()();

  /// 限时规则的每日上限毫秒（ruleType=limit 时使用）
  IntColumn get dailyLimitMillis => integer().nullable()();

  /// 是否启用
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
}

/// 目标 / 习惯（V0.4 预留）。
class Goals extends Table {
  @override
  String get tableName => 'goal';

  IntColumn get id => integer().autoIncrement()();

  /// 目标标题，如「每天专注 2 小时」
  TextColumn get title => text()();

  /// 目标类型：dailyFocus / weeklyFocus / streak
  TextColumn get type => text()();

  /// 目标值（毫秒或天数，按 type 解释）
  IntColumn get targetValue => integer()();

  IntColumn get createdAt => integer()();

  /// 归档（软删除）
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

/// 按键映射预设（设置页自定义映射的持久化）。
class KeyMapPresets extends Table {
  @override
  String get tableName => 'key_map_preset';

  IntColumn get id => integer().autoIncrement()();

  /// 预设名称
  TextColumn get name => text()();

  /// 是否为当前生效预设
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();

  /// KeyMapConfig.toJson() 的 JSON 字符串
  TextColumn get mappingJson => text()();

  IntColumn get updatedAt => integer()();
}

// ---------------------------------------------------------------- DAO

/// 专注记录 DAO 雏形。
@DriftAccessor(tables: [FocusSessions])
class FocusSessionDao extends DatabaseAccessor<AppDatabase>
    with _$FocusSessionDaoMixin {
  FocusSessionDao(super.db);

  /// 写入一条新会话，返回自增 id。
  Future<int> insertSession(FocusSessionsCompanion entry) =>
      into(focusSessions).insert(entry);

  /// 删除全部专注记录（US-E02 数据管理「一键删除」）。返回删除行数。
  Future<int> deleteAllSessions() => delete(focusSessions).go();

  /// 结算写入（R3 每轮/暂停实时入账）：按会话身份 upsert 同一行，返回行 id
  /// 供后续结算续用。
  ///
  /// 身份解析（统计翻倍根因修复）：优先用调用方传入的 [sessionId]；
  /// [sessionId] 为空（结算后立即被杀的窗口期内 prefs 里的行 id 丢失）时，
  /// **按 startAt 在库里找回同一会话的行**——同一会话的开始时刻唯一且不变，
  /// 因此永远不会因 id 丢失而插入重复行（旧实现会双插导致统计翻倍）。
  Future<int> settleSession(
    FocusSessionsCompanion entry, {
    int? sessionId,
  }) async {
    var target = sessionId;
    if (target == null && entry.startAt.present) {
      final row = await sessionByStartAt(entry.startAt.value);
      target = row?.id;
    }
    if (target == null) {
      return into(focusSessions).insert(entry);
    }
    final targetId = target;
    // 高水位保证（R13）：同一行经 10s 周期确认的 actualFocusMillis 永不回缩。
    // 终止/重开/跨天等路径曾概率性地把整轮时长覆盖成「几秒」（写侧此前无
    // 任何防回缩校验，任何一个更小的 incoming 都会直接覆盖既有值）。
    // incoming 比既有值小 = 异常来源，保留既有整行，仅返回行 id。
    final existing = await (select(focusSessions)
          ..where((t) => t.id.equals(targetId)))
        .getSingleOrNull();
    if (existing == null) {
      return into(focusSessions).insert(entry.copyWith(id: Value(targetId)));
    }
    final incoming =
        entry.actualFocusMillis.present ? entry.actualFocusMillis.value : 0;
    if (incoming < existing.actualFocusMillis) {
      return targetId;
    }
    // 异常增加防护：actual 不得超过 [startAt, endAt/now] 墙钟跨度（65s 容差）。
    final startAt =
        entry.startAt.present ? entry.startAt.value : existing.startAt;
    final endRef = entry.endAt.present && entry.endAt.value != null
        ? entry.endAt.value!
        : DateTime.now().millisecondsSinceEpoch;
    final span = endRef - startAt;
    if (incoming > span + 65000) {
      return into(focusSessions).insertOnConflictUpdate(entry.copyWith(
        id: Value(targetId),
        actualFocusMillis: Value(span > 0 ? span : 0),
      ));
    }
    return into(focusSessions).insertOnConflictUpdate(entry.copyWith(
      id: Value(targetId),
    ));
  }

  /// 按会话开始时刻查行（同 startAt 取 actualFocusMillis 最大、其次 id 最大
  /// 的一行）——活跃行恢复与结算身份解析共用。
  Future<FocusSession?> sessionByStartAt(int startAt) {
    return (select(focusSessions)
          ..where((t) => t.startAt.equals(startAt))
          ..orderBy([
            (t) => OrderingTerm.desc(t.actualFocusMillis),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 会话去重（读侧「任何时刻只记一次」保障）：同 (startAt, mode) 只保留
  /// actualFocusMillis 最大的一行。历史遗留的重复行即使未清理也不会双计。
  static List<FocusSession> dedupeByStartAt(List<FocusSession> rows) {
    final best = <String, FocusSession>{};
    for (final r in rows) {
      final key = '${r.startAt}|${r.mode}';
      final cur = best[key];
      if (cur == null || r.actualFocusMillis > cur.actualFocusMillis) {
        best[key] = r;
      }
    }
    final list = best.values.toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    return list;
  }

  /// 启动自愈：删除重复落库的会话行，同 (startAt, mode) 只保留
  /// actualFocusMillis 最大的一行（[keepId] 当前活跃行强制保留）。
  /// 返回删除行数。
  Future<int> deleteDuplicateSessions({int? keepId}) async {
    final all = await (select(focusSessions)
          ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
        .get();
    final keep = <String, FocusSession>{};
    for (final s in all) {
      final key = '${s.startAt}|${s.mode}';
      final cur = keep[key];
      if (cur == null || _preferRow(s, cur, keepId)) keep[key] = s;
    }
    var deleted = 0;
    for (final s in all) {
      if (identical(keep['${s.startAt}|${s.mode}'], s)) continue;
      await (delete(focusSessions)..where((t) => t.id.equals(s.id))).go();
      deleted++;
    }
    return deleted;
  }

  /// 去重保留优先级：活跃行 > actualFocusMillis 更大 > id 更大。
  static bool _preferRow(FocusSession a, FocusSession b, int? keepId) {
    final aActive = keepId != null && a.id == keepId;
    final bActive = keepId != null && b.id == keepId;
    if (aActive != bActive) return aActive;
    if (a.actualFocusMillis != b.actualFocusMillis) {
      return a.actualFocusMillis > b.actualFocusMillis;
    }
    return a.id > b.id;
  }

  /// 结束会话：回填结束时间与统计字段。
  Future<void> finishSession(
    int id, {
    required int endAt,
    required int actualFocusMillis,
    required int rounds,
    required bool completed,
  }) {
    return (update(focusSessions)..where((t) => t.id.equals(id))).write(
      FocusSessionsCompanion(
        endAt: Value(endAt),
        actualFocusMillis: Value(actualFocusMillis),
        rounds: Value(rounds),
        completed: Value(completed),
      ),
    );
  }

  /// 查询某日（[dayStart, dayEnd) 毫秒区间）内的所有会话。
  Future<List<FocusSession>> sessionsOfDay(int dayStart, int dayEnd) async {
    final rows = await (select(focusSessions)
          ..where((t) =>
              t.startAt.isBiggerOrEqualValue(dayStart) &
              t.startAt.isSmallerThanValue(dayEnd))
          ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
        .get();
    return dedupeByStartAt(rows);
  }

  /// 全量会话（数据导出备份用，看板 #45）。
  Future<List<FocusSession>> allSessions() {
    return (select(focusSessions)
          ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
        .get();
  }

  /// 查询任意区间 [start, end) 内的所有会话（周报/连续记录用，US-D03/D04）。
  Future<List<FocusSession>> sessionsOfRange(int start, int end) async {
    final rows = await (select(focusSessions)
          ..where((t) =>
              t.startAt.isBiggerOrEqualValue(start) &
              t.startAt.isSmallerThanValue(end))
          ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
        .get();
    return dedupeByStartAt(rows);
  }

  /// 统计某日的实际专注总毫秒。
  Future<int> totalFocusMillisOfDay(int dayStart, int dayEnd) async {
    final sessions = await sessionsOfDay(dayStart, dayEnd);
    return sessions.fold<int>(
        0, (sum, s) => sum + s.actualFocusMillis);
  }

  /// 统计某日的完成番茄数（rounds 合计，US-D01）。
  Future<int> totalRoundsOfDay(int dayStart, int dayEnd) async {
    final sessions = await sessionsOfDay(dayStart, dayEnd);
    return sessions.fold<int>(0, (sum, s) => sum + s.rounds);
  }

  /// 区间每日实际专注毫秒（周视图合并查询，性能低优先项）：
  /// 一次查询 [start, end) 内全部会话，按 startAt 归日开始日分桶，
  /// 返回 {本地零点毫秒: 当日实际专注毫秒}——替代 7 次串行单查。
  /// 按会话身份去重后再累计（同 startAt 只记一次）。
  Future<Map<int, int>> dailyFocusMillisOfRange(int start, int end) async {
    final rows = await (select(focusSessions)
          ..where((t) =>
              t.startAt.isBiggerOrEqualValue(start) &
              t.startAt.isSmallerThanValue(end)))
        .get();
    final result = <int, int>{};
    for (final s in dedupeByStartAt(rows)) {
      final t = DateTime.fromMillisecondsSinceEpoch(s.startAt);
      final dayStart =
          DateTime(t.year, t.month, t.day).millisecondsSinceEpoch;
      result[dayStart] = (result[dayStart] ?? 0) + s.actualFocusMillis;
    }
    return result;
  }

  /// 启动自愈（R8）：关闭历史遗留的悬空「进行中」行（endAt 为 null）。
  /// 这些是旧版 _finish 结算竞态的产物——真行永不关闭、幽灵行抢统计。
  /// endAt 回填为 startAt + actualFocusMillis（诚实口径：只承认已记的
  /// 实际专注时长，不把悬空跨度算作专注）。返回关闭的行数。
  /// [exceptId]：当前活跃会话 id（如有）不触碰。
  Future<int> closeOrphanOpenSessions({int? exceptId}) async {
    final orphans = await (select(focusSessions)
          ..where((t) => t.endAt.isNull()))
        .get();
    var closed = 0;
    for (final s in orphans) {
      if (exceptId != null && s.id == exceptId) continue;
      await (update(focusSessions)..where((t) => t.id.equals(s.id))).write(
        FocusSessionsCompanion(
          endAt: Value(s.startAt + s.actualFocusMillis),
        ),
      );
      closed++;
    }
    return closed;
  }

  /// 启动自愈（R8）：删除物理不可能的幽灵行——actualFocusMillis 超出
  /// [startAt, endAt] 跨度 65 秒以上（0 时长幽灵行特征：startAt≈endAt
  /// 却背着全部轮数/时长，是旧版 _finish 竞态把结算写到了清零游标上）。
  /// 返回删除的行数。
  Future<int> deleteImpossibleSessions() async {
    final finished = await (select(focusSessions)
          ..where((t) => t.endAt.isNotNull()))
        .get();
    var deleted = 0;
    for (final s in finished) {
      final span = s.endAt! - s.startAt;
      if (s.actualFocusMillis > span + 65000) {
        await (delete(focusSessions)..where((t) => t.id.equals(s.id))).go();
        deleted++;
      }
    }
    return deleted;
  }
}

// ---------------------------------------------------------------- 数据库

/// 应用数据库。
@DriftDatabase(
  tables: [FocusSessions, UsageStatDailies, AppRules, Goals, KeyMapPresets],
  daos: [FocusSessionDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 测试用：注入自定义 executor（如 NativeDatabase.memory()）。
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          // v1 → v2：focus_session 新增 mode 列（默认 'pomodoro'，存量数据兼容）
          if (from < 2) {
            await migrator.addColumn(focusSessions, focusSessions.mode);
          }
          // v2 → v3：focus_session 新增 marks_json 列（正计时打点复盘，US-B02）
          if (from < 3) {
            await migrator.addColumn(focusSessions, focusSessions.marksJson);
          }
          // v3 → v4：focus_session 新增 intervals_json 列（专注段区间，R8）
          if (from < 4) {
            await migrator.addColumn(focusSessions, focusSessions.intervalsJson);
          }
          // v4 → v5：focus_session 新增 pauses_json（中断区间，US-D02）
          // 与 tag（任务/标签，US-B05）两列
          if (from < 5) {
            await migrator.addColumn(focusSessions, focusSessions.pausesJson);
            await migrator.addColumn(focusSessions, focusSessions.tag);
          }
        },
      );
}

/// 数据库单例 Provider（platform 层；各 feature 经此取用，测试可 override）。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

LazyDatabase _openConnection() {
  // sqlite3_flutter_libs 已随依赖带入各平台原生库，无需额外配置。
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'ai_clock.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
