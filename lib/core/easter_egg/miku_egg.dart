/// 初音彩蛋（看板 #47，纯 Dart 可测）：可达化的 39 系列小彩蛋。
///
/// 边界（ADR-0005）：不是成就系统——无等级、无累积奖励、无养成，
/// 只是在已达成的真实数据上叠一句 Miku 彩蛋文案。优先级：取最先命中者。
library;

/// 计算当前应展示的彩蛋文案；无命中返回 null。
///
/// 规则（按优先级）：
/// 1. 3 月 9 日「ミクの日」（39 谐音梗，年度大彩蛋）；
/// 2. 连续记录满 39 天；
/// 3. 今日专注满 39 分钟（日常可达的小彩蛋）。
String? mikuEasterEgg({
  required DateTime now,
  required int todayFocusMillis,
  required int streakDays,
}) {
  if (now.month == 3 && now.day == 9) {
    return '3 月 9 日「ミクの日」——葱色全天为你点亮！';
  }
  if (streakDays == 39) {
    return '已连续 39 天——Miku 为你鼓掌！';
  }
  if (todayFocusMillis >= 39 * 60 * 1000) {
    return '今日专注已达 39 分钟，ミク为你点赞！';
  }
  return null;
}
