/// 暂停超时释放策略（US-C02）单测。
///
/// 语义：暂停超过阈值（默认 10 分钟，可配置）→ 释放 MediaSession，
/// 按键归还音乐 App，但专注记录不作废；用户继续时重新霸占。
library;

import 'package:ai_clock/core/timer/pause_release_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PauseReleasePolicy.shouldRelease', () {
    const threshold = Duration(minutes: 10);

    test('暂停未超阈值不释放', () {
      expect(
        PauseReleasePolicy.shouldRelease(
          pausedAtMillis: 1000,
          nowMillis: 1000 + const Duration(minutes: 9, seconds: 59).inMilliseconds,
          threshold: threshold,
        ),
        isFalse,
      );
    });

    test('暂停达到阈值即释放（边界含等于）', () {
      expect(
        PauseReleasePolicy.shouldRelease(
          pausedAtMillis: 1000,
          nowMillis: 1000 + const Duration(minutes: 10).inMilliseconds,
          threshold: threshold,
        ),
        isTrue,
      );
    });

    test('暂停远超阈值释放', () {
      expect(
        PauseReleasePolicy.shouldRelease(
          pausedAtMillis: 0,
          nowMillis: const Duration(hours: 2).inMilliseconds,
          threshold: threshold,
        ),
        isTrue,
      );
    });

    test('阈值可配置：5 分钟阈值下 7 分钟暂停即释放', () {
      expect(
        PauseReleasePolicy.shouldRelease(
          pausedAtMillis: 0,
          nowMillis: const Duration(minutes: 7).inMilliseconds,
          threshold: const Duration(minutes: 5),
        ),
        isTrue,
      );
    });
  });

  group('PauseReleasePolicy.shouldAutoFinish（不活跃自动结束，R7）', () {
    const threshold = Duration(minutes: 60);

    test('暂停 59 分钟不结束（正常轮间歇不受影响）', () {
      expect(
        PauseReleasePolicy.shouldAutoFinish(
          pausedAtMillis: 0,
          nowMillis: const Duration(minutes: 59, seconds: 59).inMilliseconds,
          threshold: threshold,
        ),
        isFalse,
      );
    });

    test('暂停达到 60 分钟即结束（边界含等于）', () {
      expect(
        PauseReleasePolicy.shouldAutoFinish(
          pausedAtMillis: 1000,
          nowMillis: 1000 + const Duration(minutes: 60).inMilliseconds,
          threshold: threshold,
        ),
        isTrue,
      );
    });

    test('午休级不活跃（2 小时）结束——幽灵 resume 累积兜底', () {
      expect(
        PauseReleasePolicy.shouldAutoFinish(
          pausedAtMillis: 0,
          nowMillis: const Duration(hours: 2).inMilliseconds,
          threshold: threshold,
        ),
        isTrue,
      );
    });

    test('默认阈值常量 = 60 分钟', () {
      expect(PauseReleasePolicy.defaultAutoFinishThreshold,
          const Duration(minutes: 60));
    });
  });
}
