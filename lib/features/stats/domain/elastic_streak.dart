/// 弹性连续记录（US-D03，纯 Dart 可测）。
///
/// 规则：每周允许 [bufferPerWeek] 天缓冲（默认 2），断签不清零——
/// 任意 7 天窗口内缺勤数超过缓冲额度，连续才在该日之前断开。
library;

/// 连续记录计算结果。
class StreakResult {
  const StreakResult({required this.days, required this.bufferUsed});

  /// 当前连续天数（含缓冲日）。今天尚无专注时锚定昨天——
  /// 今天还没过完，不该破坏连续。
  final int days;

  /// 当前 7 天窗口（锚点向前 6 天）内已用的缓冲天数。
  final int bufferUsed;
}

const int _dayMillis = 24 * 60 * 60 * 1000;

/// 由「有专注的本地零点毫秒集合」计算弹性连续。
///
/// 算法：锚点 = 今天有专注则今天、否则昨天；从锚点逐日回看——
/// 专注日计入链条；缺勤日消耗缓冲（其后 6 天内缺勤数 +1 超过额度则断开）。
/// 连续天数 = 锚点到链条内最老专注日的跨度（含中间缓冲日）；
/// 链条尾部的缓冲日不计入天数——「已连续 N 天」必须锚在真实专注日上，
/// 否则 3 天专注 + 2 天缓冲会被吹成 5 天（不诚实）。
StreakResult elasticStreak(
  Set<int> focusDays,
  DateTime now, {
  int bufferPerWeek = 2,
}) {
  final today = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  final anchor = focusDays.contains(today) ? today : today - _dayMillis;

  var cursor = anchor;
  int? oldestFocusDay; // 链条内最老的专注日
  final misses = <int>[]; // 缺勤日零点毫秒，按时间倒序
  while (anchor - cursor <= 4000 * _dayMillis) {
    if (focusDays.contains(cursor)) {
      oldestFocusDay = cursor;
    } else {
      // 本缺勤日 + 其后 6 天内的缺勤数 = 该 7 天窗口的总缺勤
      final windowMisses =
          misses.where((m) => m - cursor < 7 * _dayMillis).length + 1;
      if (windowMisses > bufferPerWeek) break; // 链条在 cursor 之前断开
      misses.add(cursor);
    }
    cursor -= _dayMillis;
  }

  if (oldestFocusDay == null) {
    return const StreakResult(days: 0, bufferUsed: 0);
  }
  final oldest = oldestFocusDay;
  final days = (anchor - oldest) ~/ _dayMillis + 1;
  // 缓冲用量只计连续跨度内的缺勤日（跨度外的缓冲消耗未兑现为连续，不展示）
  final bufferUsed =
      misses.where((m) => m >= oldest && m <= anchor).length;
  return StreakResult(days: days, bufferUsed: bufferUsed);
}
