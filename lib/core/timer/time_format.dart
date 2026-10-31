/// 时长显示格式化（mm:ss / h:mm:ss），UI 与通知共用。
library;

/// 把 [d] 格式化为 `mm:ss`（不足一小时）或 `h:mm:ss`。
String formatDurationClock(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = d.inHours;
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// 倒计时剩余时间的分钟级文本（向上取整：剩几秒也算「1 分」）。
/// 通知栏专用：M500 ROM 对每次 notify() 整窗重绘，秒级文本会让整个
/// 通知每秒闪烁（真机反馈 R2）；分钟级把刷新率降到每分钟一次。
String formatRemainingMinutes(Duration d) {
  final millis = d.inMilliseconds;
  if (millis <= 0) return '0 分';
  final minutes = (millis + 59999) ~/ 60000;
  return '$minutes 分';
}

/// 正计时累计时间的分钟级文本（向下取整，开跑未满 1 分钟显示「0 分」）。
/// 通知栏专用，理由同 [formatRemainingMinutes]。
String formatElapsedMinutes(Duration d) {
  final minutes = d.inMilliseconds ~/ 60000;
  return '$minutes 分';
}

/// 两个毫秒时间戳是否属于同一本地日（按设备时区的年月日比较）。
/// 跨天僵尸会话守卫用（真机反馈 R5/R6）：恢复出的会话 startAt 若属于
/// 更早日期，统计按 startAt 归当日会让「今天」永远为零。
bool isSameLocalDay(int aMillis, int bMillis) {
  final a = DateTime.fromMillisecondsSinceEpoch(aMillis);
  final b = DateTime.fromMillisecondsSinceEpoch(bMillis);
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// 时长文本（精确到秒）：「1h 2m 3s」/「2m 3s」/「3s」。
/// 统计页与详细统计页共用（真机反馈 R4：只到分钟会让短会话显示「0m」，R8 提取共用）。
String formatDurationText(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}
