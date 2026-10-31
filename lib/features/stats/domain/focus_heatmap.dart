/// 近 12 周专注热力图：统计页「坚持度」可视化（看板 #37 ratio 模型）。
///
/// 用户设定每日及格线（默认 120 分钟），格子值 = 当日专注 / 及格线：
///   -1    = 未来日；0 = 无专注；
///   (0,1) = 未达标——着色 alpha = ratio²（差距二次方放大，差越多越浅）；
///   >=1   = 达标满色，超出部分向白混合 (ratio-1)²（超常越多越亮）。
/// 二次方语义：及格线附近的小差距几乎不可见，大差距被显著放大——
/// 一眼只看到「明显不足」与「明显超标」，中间态不制造焦虑。
library;

/// 当日专注毫秒 / 及格线毫秒 → 热力比值（0 = 无数据）。
double focusHeatRatio(int millis, int goalMillis) {
  if (millis <= 0 || goalMillis <= 0) return 0;
  return millis / goalMillis;
}

/// 日期 → 统计键（与 FocusSessionDao.dailyFocusMillisOfRange 的 key
/// 同格式：本地零点的 millisecondsSinceEpoch）。
int heatDateKey(DateTime day) =>
    DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;

/// 默认每日及格线：120 分钟（约 5 个 25 分钟番茄）。
const kDefaultDailyGoalMinutes = 120;

/// 构建 weeks×7 热力网格：`[week][weekday]`，week 0 = 最早一周，
/// weekday 0 = 周一 … 6 = 周日；格子 = 比值（本周列晚于 [today] 为 -1）。
List<List<double>> buildFocusHeatmap(
  Map<int, int> dailyMillis,
  DateTime today, {
  int weeks = 12,
  int goalMillis = kDefaultDailyGoalMinutes * 60 * 1000,
}) {
  final todayOnly = DateTime(today.year, today.month, today.day);
  // DateTime.weekday：周一 = 1 … 周日 = 7
  final thisMonday =
      todayOnly.subtract(Duration(days: todayOnly.weekday - 1));
  final firstMonday = thisMonday.subtract(Duration(days: 7 * (weeks - 1)));
  return List.generate(
    weeks,
    (w) => List.generate(7, (d) {
      final day = firstMonday.add(Duration(days: w * 7 + d));
      if (day.isAfter(todayOnly)) return -1.0;
      return focusHeatRatio(dailyMillis[heatDateKey(day)] ?? 0, goalMillis);
    }),
  );
}
