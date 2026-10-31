/// 模式分发单测：同一命令在不同计时模式下的语义改写（ADR-0005）。
///
/// 规则（技术架构设计与 PRD 按键语义映射表）：
/// - 上一曲键默认映射为 addFiveMinutes；正计时模式下改写为 tickMark（打点）；
/// - 正计时没有「阶段」概念，skipPhase / previousPhase 在正计时下无意义，
///   分发为 ignored（无效果也不给反馈，避免误导）；
/// - 番茄倒计时模式下一切命令原样透传。
library;

import 'package:ai_clock/core/commands/app_command.dart';
import 'package:ai_clock/core/commands/mode_dispatch.dart';
import 'package:ai_clock/core/timer/timer_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveForMode · 番茄倒计时模式', () {
    test('所有命令原样透传', () {
      for (final c in AppCommand.values) {
        expect(resolveForMode(c, TimerMode.pomodoro), c, reason: '$c 不应被改写');
      }
    });
  });

  group('resolveForMode · 正计时模式', () {
    test('addFiveMinutes 改写为 tickMark（上一曲=打点）', () {
      expect(resolveForMode(AppCommand.addFiveMinutes, TimerMode.countUp),
          AppCommand.tickMark);
    });

    test('skipPhase 无阶段概念，降级为 ignored', () {
      expect(resolveForMode(AppCommand.skipPhase, TimerMode.countUp),
          AppCommand.ignored);
    });

    test('开始/暂停、结束、打点、转发下一首、ignored 原样透传', () {
      for (final c in [
        AppCommand.toggleStartPause,
        AppCommand.finishSession,
        AppCommand.tickMark,
        AppCommand.forwardNext, // 与计时模式无关：转发给系统音乐 App
        AppCommand.ignored,
      ]) {
        expect(resolveForMode(c, TimerMode.countUp), c, reason: '$c 不应被改写');
      }
    });
  });
}
