/// 时长格式化单测（含真机反馈 R2 新增的通知栏分钟级文本）。
library;

import 'package:ai_clock/core/timer/time_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDurationClock', () {
    test('不足一小时 mm:ss；超过一小时 h:mm:ss', () {
      expect(formatDurationClock(const Duration(minutes: 24, seconds: 59)),
          '24:59');
      expect(formatDurationClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });
  });

  group('formatRemainingMinutes（倒计时，通知栏分钟级）', () {
    test('向上取整：剩几秒也算 1 分，避免显示 0 分误导', () {
      expect(formatRemainingMinutes(const Duration(minutes: 24, seconds: 30)),
          '25 分');
      expect(formatRemainingMinutes(const Duration(seconds: 30)), '1 分');
      expect(formatRemainingMinutes(Duration.zero), '0 分');
      expect(formatRemainingMinutes(const Duration(minutes: 5)), '5 分');
    });
  });

  group('formatElapsedMinutes（正计时，通知栏分钟级）', () {
    test('向下取整：开跑未满 1 分钟显示 0 分', () {
      expect(formatElapsedMinutes(const Duration(seconds: 59)), '0 分');
      expect(formatElapsedMinutes(const Duration(minutes: 47, seconds: 30)),
          '47 分');
    });
  });

  group('isSameLocalDay（跨天僵尸会话守卫，R6）', () {
    test('同一本地日的不同时刻为 true；跨零点为 false', () {
      final morning = DateTime(2026, 7, 26, 8).millisecondsSinceEpoch;
      final night = DateTime(2026, 7, 26, 23, 59).millisecondsSinceEpoch;
      final nextDay = DateTime(2026, 7, 27, 0, 1).millisecondsSinceEpoch;
      expect(isSameLocalDay(morning, night), isTrue);
      expect(isSameLocalDay(night, nextDay), isFalse);
    });

    test('跨月/跨年边界正确判定', () {
      final monthEnd = DateTime(2026, 7, 31, 23).millisecondsSinceEpoch;
      final monthStart = DateTime(2026, 8, 1, 1).millisecondsSinceEpoch;
      final yearEnd = DateTime(2026, 12, 31, 23).millisecondsSinceEpoch;
      final yearStart = DateTime(2027, 1, 1, 1).millisecondsSinceEpoch;
      expect(isSameLocalDay(monthEnd, monthStart), isFalse);
      expect(isSameLocalDay(yearEnd, yearStart), isFalse);
    });
  });
}
