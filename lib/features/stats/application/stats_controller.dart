/// 统计控制器：今日/本周专注时长与各应用使用时长。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/easter_egg/miku_egg.dart';
import '../../../platform/db/app_database.dart';
import '../../../platform/prefs/prefs_provider.dart';
import '../domain/daily_summary.dart';
import '../domain/elastic_streak.dart';
import '../domain/focus_heatmap.dart';
import '../domain/focus_interruption.dart';
import '../domain/usage_stats_source.dart';
import '../domain/weekly_report.dart';

/// 使用数据源（默认真机实现；测试时 override 为 FakeUsageStatsSource）。
final usageStatsSourceProvider =
    Provider<UsageStatsSource>((ref) => UsageStatsSourceImpl());

/// 今日专注总时长（来自 drift focus_session）。
final todayFocusProvider = FutureProvider<Duration>((ref) async {
  final dao = ref.watch(appDatabaseProvider).focusSessionDao;
  final now = DateTime.now();
  final dayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  final dayEnd = dayStart + const Duration(days: 1).inMilliseconds;
  final millis = await dao.totalFocusMillisOfDay(dayStart, dayEnd);
  return Duration(milliseconds: millis);
});

/// 今日完成番茄数（focus_session.rounds 当日合计，US-D01）。
final todayRoundsProvider = FutureProvider<int>((ref) async {
  final dao = ref.watch(appDatabaseProvider).focusSessionDao;
  final now = DateTime.now();
  final dayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  final dayEnd = dayStart + const Duration(days: 1).inMilliseconds;
  return dao.totalRoundsOfDay(dayStart, dayEnd);
});

/// 最近 7 天每日专注时长（柱状图数据）。
/// 性能低优先项：合并为一次区间查询 + Dart 分桶（原 7 次串行单查）。
final weekFocusProvider = FutureProvider<List<Duration>>((ref) async {
  final dao = ref.watch(appDatabaseProvider).focusSessionDao;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  const dayMillis = 24 * 60 * 60 * 1000; // Duration.inMilliseconds 不是 const 表达式
  final weekStart =
      today.subtract(const Duration(days: 6)).millisecondsSinceEpoch;
  final totals = await dao.dailyFocusMillisOfRange(
      weekStart, today.millisecondsSinceEpoch + dayMillis);
  return <Duration>[
    for (var i = 6; i >= 0; i--)
      Duration(
          milliseconds: totals[today
                  .subtract(Duration(days: i))
                  .millisecondsSinceEpoch] ??
              0),
  ];
});

/// 指定日期的全部专注会话（详细时间统计页，看板 #19 幽灵排查工具）。
/// 入参为任意时刻，内部归一到本地零点；会话按 startAt 归属当日
/// （跨天会话整段归开始日，AGENT.md §7 已记录的归因限制）。
final daySessionsProvider =
    FutureProvider.family<List<FocusSession>, DateTime>((ref, day) async {
  final dao = ref.watch(appDatabaseProvider).focusSessionDao;
  final dayStart = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
  final dayEnd = dayStart + const Duration(days: 1).inMilliseconds;
  return dao.sessionsOfDay(dayStart, dayEnd);
});

/// 弹性连续记录（US-D03）：回看 400 天的有专注日期集合。
final streakProvider = FutureProvider<StreakResult>((ref) async {
  final dao = ref.watch(appDatabaseProvider).focusSessionDao;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final rangeStart =
      today.subtract(const Duration(days: 400)).millisecondsSinceEpoch;
  final totals = await dao.dailyFocusMillisOfRange(rangeStart,
      today.millisecondsSinceEpoch + const Duration(days: 1).inMilliseconds);
  final focusDays = <int>{
    for (final e in totals.entries)
      if (e.value > 0) e.key,
  };
  return elasticStreak(focusDays, now);
});

/// 每周专注报告（US-D04）：本周 vs 上周 + 最专注时段。
final weeklyReportProvider = FutureProvider<WeeklyReport>((ref) async {
  final dao = ref.watch(appDatabaseProvider).focusSessionDao;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
  final sessions = await dao.sessionsOfRange(
    thisWeekStart.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
    thisWeekStart.add(const Duration(days: 7)).millisecondsSinceEpoch,
  );
  return buildWeeklyReport(
    [for (final s in sessions) (s.startAt, s.actualFocusMillis)],
    now,
  );
});

/// 指定日期的小结（看板 #46：详细页「今日小结」卡）。入参归一本地零点。
final dailySummaryProvider =
    FutureProvider.family<DailySummary, DateTime>((ref, day) async {
  final sessions = await ref.watch(daySessionsProvider(day).future);
  return buildDailySummary([
    for (final s in sessions)
      DailySessionFact(
        startAtMillis: s.startAt,
        focusMillis: s.actualFocusMillis,
        rounds: s.rounds,
        pauses: parseInterruptions(s.pausesJson),
      ),
  ]);
});

/// 初音彩蛋（看板 #47）：39 系列小彩蛋文案，无命中为 null。
final easterEggProvider = FutureProvider<String?>((ref) async {
  final focus = await ref.watch(todayFocusProvider.future);
  final streak = await ref.watch(streakProvider.future);
  return mikuEasterEgg(
    now: DateTime.now(),
    todayFocusMillis: focus.inMilliseconds,
    streakDays: streak.days,
  );
});

/// 「使用情况访问」权限状态（US-E01/E02：授权引导与数据管理页共用）。
final usagePermissionProvider = FutureProvider<bool>(
    (ref) => ref.watch(usageStatsSourceProvider).hasPermission());

/// 今日各应用使用时长 Top 3 + 屏幕使用总时长。
///
/// 收敛到 Top 3（原 5）并额外给出总时长：使用统计页要显示
/// 「专注 / 屏幕」的比值，只报单应用时长看不出「时间到底花在哪儿」。
final todayAppUsageProvider =
    FutureProvider<({List<AppUsageInfo> top, int totalMillis})>((ref) async {
  // 依赖权限状态：授权/撤销后自动重查（US-E01 引导返回即刷新）
  final granted = await ref.watch(usagePermissionProvider.future);
  if (!granted) return (top: const <AppUsageInfo>[], totalMillis: 0);
  final source = ref.watch(usageStatsSourceProvider);
  final now = DateTime.now();
  final dayStart = DateTime(now.year, now.month, now.day);
  final list = await source.queryUsage(dayStart, now);
  var total = 0;
  for (final info in list) {
    total += info.foregroundMillis;
  }
  list.sort((a, b) => b.foregroundMillis.compareTo(a.foregroundMillis));
  return (top: list.take(3).toList(), totalMillis: total);
});

/// 近 12 周专注热力图（看板 #34/#37）：grid = 12 列×7 行比值
/// （列=周、行=周一~周日，末列=本周，未来日 = -1；比值 = 当日/及格线）；
/// millis = 零点毫秒 key → 当日专注毫秒（点击格子查当天详情用）。
final heatmapProvider =
    FutureProvider<({List<List<double>> grid, Map<int, int> millis})>(
        (ref) async {
  final goalMinutes = ref.watch(dailyGoalMinutesProvider);
  final dao = ref.watch(appDatabaseProvider).focusSessionDao;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thisMonday = today.subtract(Duration(days: today.weekday - 1));
  final rangeStart = thisMonday.subtract(const Duration(days: 7 * 11));
  final totals = await dao.dailyFocusMillisOfRange(
      rangeStart.millisecondsSinceEpoch,
      today.millisecondsSinceEpoch + const Duration(days: 1).inMilliseconds);
  return (
    grid: buildFocusHeatmap(totals, now, goalMillis: goalMinutes * 60 * 1000),
    millis: totals,
  );
});

/// 每日及格线分钟数（热力图 ratio 模型基准，看板 #37 用户可调）。
final dailyGoalMinutesProvider = StateNotifierProvider<DailyGoalNotifier, int>(
    (ref) => DailyGoalNotifier(ref.watch(sharedPreferencesProvider)));

/// 及格线的读写与持久化（15-600 分钟（10h，2026-10-03 用户要求），缺失/非法回退 120）。
class DailyGoalNotifier extends StateNotifier<int> {
  DailyGoalNotifier(this._prefs)
      : super((_prefs.getInt(_kKey) ?? kDefaultDailyGoalMinutes)
            .clamp(15, 600));

  static const _kKey = 'stats_daily_goal_minutes';
  final SharedPreferences _prefs;

  Future<void> set(int minutes) async {
    final v = minutes.clamp(15, 600);
    state = v;
    await _prefs.setInt(_kKey, v);
  }
}
