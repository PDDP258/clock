/// 多击计数（800ms 窗口）与按键 → 命令映射用例。
///
/// ClickGrouper 与 CommandBus 均为纯 Dart：多击窗口通过注入
/// 手动调度器控制，映射表通过 KeyMapConfig 直接断言。
library;

import 'dart:convert';

import 'package:ai_clock/core/commands/app_command.dart';
import 'package:ai_clock/core/media/media_key_event.dart';
import 'package:flutter_test/flutter_test.dart';

/// 手动调度器：捕获窗口回调，测试自行决定何时「到期」。
class ManualScheduler {
  void Function()? pending;

  void call(Duration delay, void Function() callback) {
    pending = callback;
  }

  /// 模拟窗口到期。
  void fire() {
    final cb = pending;
    pending = null;
    cb?.call();
  }
}

void main() {
  group('ClickGrouper 多击分组', () {
    late ManualScheduler scheduler;
    late List<MediaKeyEvent> events;
    late ClickGrouper grouper;

    setUp(() {
      scheduler = ManualScheduler();
      events = [];
      grouper = ClickGrouper(
        onResolved: events.add,
        scheduler: scheduler.call,
      );
    });

    test('按 1 次 → 窗口到期结算为单按', () {
      grouper.tap();
      scheduler.fire();
      expect(events, [MediaKeyEvent.singleTap]);
    });

    test('窗口内按 2 次 → 双按', () {
      grouper.tap();
      grouper.tap(); // 第二次击键会武装新回调，旧回调自动作废
      scheduler.fire();
      expect(events, [MediaKeyEvent.doubleTap]);
    });

    test('窗口内按 3 次 → 三按', () {
      grouper
        ..tap()
        ..tap()
        ..tap();
      scheduler.fire();
      expect(events, [MediaKeyEvent.tripleTap]);
    });

    test('旧窗口回调在窗口内有新击键时作废', () {
      grouper.tap();
      final firstFire = scheduler.pending;
      grouper.tap(); // 新击键使 firstFire 作废
      firstFire!.call(); // 模拟旧回调迟到触发
      expect(events, isEmpty); // 不应结算单按
      scheduler.fire();
      expect(events, [MediaKeyEvent.doubleTap]);
    });

    test('flushNow 立即结算（长按抢占等兜底路径）', () {
      grouper
        ..tap()
        ..tap();
      grouper.flushNow();
      expect(events, [MediaKeyEvent.doubleTap]);
      expect(grouper.pendingCount, 0);
    });
  });

  group('KeyMapConfig 默认映射', () {
    test('默认映射符合产品定义（ADR-0005 + 真机双按转发）', () {
      final map = KeyMapConfig.defaults().mapping;
      // 单按=开始/暂停，双按=音乐下一首，长按=结束并保存，
      // 下一曲=跳过，上一曲=+5 分钟；三按保留解析能力不映射
      expect(map[MediaKeyEvent.singleTap], AppCommand.toggleStartPause);
      expect(map[MediaKeyEvent.doubleTap], AppCommand.forwardNext);
      expect(map[MediaKeyEvent.longPress], AppCommand.finishSession);
      expect(map[MediaKeyEvent.next], AppCommand.skipPhase);
      expect(map[MediaKeyEvent.previous], AppCommand.addFiveMinutes);
      expect(map[MediaKeyEvent.tripleTap], isNull);
    });

    test('JSON 序列化往返一致', () {
      final original = KeyMapConfig.defaults();
      final restored = KeyMapConfig.fromJson(original.toJson());
      expect(restored.mapping, original.mapping);
    });

    test('fromJson 容忍未知键名与未知命令名（丢弃而非崩溃）', () {
      final restored = KeyMapConfig.fromJson(<String, dynamic>{
        'singleTap': 'toggleStartPause',
        'unknownEvent': 'skipPhase', // 未来版本的事件名
        'next': 'unknownCommand', // 未来版本的命令名
      });
      expect(restored.mapping.length, 1);
      expect(restored.mapping[MediaKeyEvent.singleTap],
          AppCommand.toggleStartPause);
    });

    test('持久化恢复：null 与损坏 JSON 均回退出厂默认（US-A08）', () {
      expect(keyMapFromStorage(null).mapping,
          KeyMapConfig.defaults().mapping);
      expect(keyMapFromStorage('not-json{{{').mapping,
          KeyMapConfig.defaults().mapping);
    });

    test('持久化恢复：自定义映射 JSON 字符串往返一致（US-A08）', () {
      final custom = KeyMapConfig.defaults()
          .remap(MediaKeyEvent.doubleTap, AppCommand.skipPhase);
      final restored = keyMapFromStorage(jsonEncode(custom.toJson()));
      expect(restored.mapping, custom.mapping);
      expect(restored.bindsMultiTap, isTrue);
    });

    test('默认映射绑定双按（音乐下一首），单按经 300ms 窗口结算', () {
      expect(KeyMapConfig.defaults().bindsMultiTap, isTrue);
    });

    test('解绑全部多击手势后单按可绕过窗口立即下发（编辑器解绑路径）', () {
      final map = KeyMapConfig(
        mapping: Map<MediaKeyEvent, AppCommand>.of(
            KeyMapConfig.defaults().mapping)
          ..remove(MediaKeyEvent.doubleTap),
      );
      expect(map.bindsMultiTap, isFalse);
    });

    test('绑定双按或三按后，单按需回退窗口判定', () {
      var map = KeyMapConfig.defaults()
          .remap(MediaKeyEvent.doubleTap, AppCommand.skipPhase);
      expect(map.bindsMultiTap, isTrue);
      map = KeyMapConfig.defaults()
          .remap(MediaKeyEvent.tripleTap, AppCommand.skipPhase);
      expect(map.bindsMultiTap, isTrue);
    });
  });

  group('CommandBus 命令分发', () {
    test('按键事件按映射解析为命令并广播', () async {
      final bus = CommandBus();
      final received = <AppCommand>[];
      final sub = bus.commands.listen(received.add);

      expect(bus.dispatchKey(MediaKeyEvent.singleTap),
          AppCommand.toggleStartPause);
      expect(bus.dispatchKey(MediaKeyEvent.longPress),
          AppCommand.finishSession);

      await Future<void>.delayed(Duration.zero);
      expect(received,
          [AppCommand.toggleStartPause, AppCommand.finishSession]);
      await sub.cancel();
      await bus.dispose();
    });

    test('重映射后新映射立即生效', () {
      final bus = CommandBus();
      bus.keyMap =
          bus.keyMap.remap(MediaKeyEvent.doubleTap, AppCommand.skipPhase);

      expect(bus.dispatchKey(MediaKeyEvent.doubleTap),
          AppCommand.skipPhase);
      bus.dispose();
    });

    test('未映射按键解析为 ignored 且不广播', () async {
      final bus = CommandBus(
          keyMap: const KeyMapConfig(mapping: <MediaKeyEvent, AppCommand>{}));
      final received = <AppCommand>[];
      final sub = bus.commands.listen(received.add);

      expect(bus.dispatchKey(MediaKeyEvent.singleTap), AppCommand.ignored);
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
      await sub.cancel();
      await bus.dispose();
    });
  });
}
