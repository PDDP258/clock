/// 模式分发：把 CommandBus 发来的中性命令按当前计时模式改写语义。
///
/// 规则见 ADR-0005 与 PRD 按键语义映射表：
/// - 「上一曲」默认映射为 [AppCommand.addFiveMinutes]，正计时模式下
///   由本函数改写为 [AppCommand.tickMark]（打点）；番茄模式保持 +5 分钟；
/// - 正计时无阶段概念，[AppCommand.skipPhase] 降级为
///   [AppCommand.ignored]（无效果也不触发反馈，避免误导用户）。
///
/// 纯 Dart、纯函数，可独立单测（test/mode_dispatch_test.dart）。
library;

import '../timer/timer_mode.dart';
import 'app_command.dart';

/// 按 [mode] 解析 [command] 的实际语义。
AppCommand resolveForMode(AppCommand command, TimerMode mode) {
  if (mode == TimerMode.countUp) {
    return switch (command) {
      AppCommand.addFiveMinutes => AppCommand.tickMark,
      AppCommand.skipPhase => AppCommand.ignored,
      _ => command,
    };
  }
  return command;
}
