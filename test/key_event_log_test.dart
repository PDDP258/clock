/// 按键自检日志（US-G02）单测：keyCode 推导、容量裁剪、流式通知。
library;

import 'package:ai_clock/core/commands/app_command.dart';
import 'package:ai_clock/core/media/key_event_log.dart';
import 'package:ai_clock/core/media/media_key_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('keyCodeOf：语义事件 → 出厂键码（CONTEXT.md 按键直连）', () {
    test('播放/暂停键的四种手势都是 85', () {
      for (final e in [
        MediaKeyEvent.singleTap,
        MediaKeyEvent.doubleTap,
        MediaKeyEvent.tripleTap,
        MediaKeyEvent.longPress,
      ]) {
        expect(keyCodeOf(e), 85, reason: '$e 应来自播放/暂停键');
      }
    });

    test('下一曲 87、上一曲 88', () {
      expect(keyCodeOf(MediaKeyEvent.next), 87);
      expect(keyCodeOf(MediaKeyEvent.previous), 88);
    });
  });

  group('KeyEventLog', () {
    test('record 生成含三要素的条目（键码/语义/命令），最新在前', () {
      final log = KeyEventLog();
      log.record(MediaKeyEvent.next, AppCommand.skipPhase);
      log.record(MediaKeyEvent.singleTap, AppCommand.toggleStartPause);

      final entries = log.entries;
      expect(entries, hasLength(2));
      expect(entries.first.keyCode, 85); // 最新在前
      expect(entries.first.event, MediaKeyEvent.singleTap);
      expect(entries.first.command, AppCommand.toggleStartPause);
      expect(entries.last.keyCode, 87);
    });

    test('超出容量裁剪最旧条目', () {
      final log = KeyEventLog(capacity: 3);
      for (var i = 0; i < 5; i++) {
        log.record(MediaKeyEvent.next, AppCommand.skipPhase);
      }
      expect(log.entries, hasLength(3));
    });

    test('stream 在 record 时发出最新列表快照', () async {
      final log = KeyEventLog();
      final future = log.stream.first;
      log.record(MediaKeyEvent.previous, AppCommand.addFiveMinutes);
      final snapshot = await future;
      expect(snapshot, hasLength(1));
      expect(snapshot.first.keyCode, 88);
      await log.dispose();
    });

    test('clear 清空日志', () {
      final log = KeyEventLog();
      log.record(MediaKeyEvent.next, AppCommand.skipPhase);
      log.clear();
      expect(log.entries, isEmpty);
    });
  });
}
