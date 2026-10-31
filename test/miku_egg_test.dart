/// 初音彩蛋规则单测（看板 #47）+ 庆祝音反馈策略（celebrate 事件）。
library;

import 'package:ai_clock/core/easter_egg/miku_egg.dart';
import 'package:ai_clock/core/feedback/key_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mikuEasterEgg', () {
    test('3 月 9 日：年度大彩蛋（优先级最高）', () {
      final msg = mikuEasterEgg(
          now: DateTime(2026, 3, 9),
          todayFocusMillis: 60 * 60000,
          streakDays: 39);
      expect(msg, contains('ミクの日'));
    });

    test('连续 39 天彩蛋', () {
      final msg = mikuEasterEgg(
          now: DateTime(2026, 9, 12), todayFocusMillis: 0, streakDays: 39);
      expect(msg, contains('39 天'));
    });

    test('今日满 39 分钟彩蛋（日常可达）', () {
      final msg = mikuEasterEgg(
          now: DateTime(2026, 9, 12),
          todayFocusMillis: 39 * 60000,
          streakDays: 3);
      expect(msg, contains('39 分钟'));
    });

    test('未达线：null', () {
      expect(
          mikuEasterEgg(
              now: DateTime(2026, 9, 12),
              todayFocusMillis: 38 * 60000,
              streakDays: 3),
          isNull);
    });
  });

  group('FeedbackEvent.celebrate', () {
    test('庆祝音资产与开关门控（随阶段提醒音开关）', () {
      expect(FeedbackPolicy.toneAssetFor(FeedbackEvent.celebrate),
          'assets/audio/tone_celebrate.wav');
      // phaseAlertOn 关闭时庆祝音也静默
      final plan = FeedbackPolicy.decide(
          KeyFeedbackSettings.defaults.copyWith(phaseAlertOn: false),
          FeedbackEvent.celebrate);
      expect(plan.toneAsset, isNull);
      // 默认开
      expect(
          FeedbackPolicy.decide(KeyFeedbackSettings.defaults,
                  FeedbackEvent.celebrate)
              .toneAsset,
          isNotNull);
    });
  });
}
