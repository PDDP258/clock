/// 计时模式：产品边界只开放两种（ADR-0005）。
///
/// 工程扩展点（技术架构设计 §9.5）：每种模式一个独立纯 Dart 引擎类，
/// 新增模式 = 扩展本枚举 + 新建引擎文件 + FocusController 装配处注入，
/// 已有引擎与测试零改动。
library;

/// 计时模式枚举。
enum TimerMode {
  /// 番茄倒计时（默认 25/5，4 轮后长休）
  pomodoro,

  /// 正计时（不限时专注，支持打点标记）
  countUp,
}

/// 展示与持久化辅助。
extension TimerModeX on TimerMode {
  /// 中文展示名
  String get label => switch (this) {
        TimerMode.pomodoro => '番茄倒计时',
        TimerMode.countUp => '正计时',
      };

  /// 持久化用键（shared_preferences）
  String get storageKey => name;

  /// 从持久化值恢复；非法值回退默认（番茄）。
  static TimerMode fromStorageKey(String? key) =>
      TimerMode.values.asNameMap()[key] ?? TimerMode.pomodoro;
}
