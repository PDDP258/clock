/// core_feedback 纯 Dart 单测：设置序列化、事件→音型映射、开关决策。
///
/// 2026-10-01 用户口径：震动通道整体移除，反馈只剩声音通道。
library;

import 'package:ai_clock/core/feedback/key_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeyFeedbackSettings', () {
    test('默认开关全开', () {
      const s = KeyFeedbackSettings.defaults;
      expect(s.keySoundOn, isTrue);
      expect(s.phaseAlertOn, isTrue);
    });

    test('toJson/fromJson 往返一致', () {
      const s = KeyFeedbackSettings(
        keySoundOn: false,
        phaseAlertOn: false,
      );
      final restored = KeyFeedbackSettings.fromJson(s.toJson());
      expect(restored.keySoundOn, isFalse);
      expect(restored.phaseAlertOn, isFalse);
    });

    test('fromJson 缺字段时回退默认（老版本数据兼容）', () {
      final s = KeyFeedbackSettings.fromJson(const {});
      expect(s.keySoundOn, isTrue);
      expect(s.phaseAlertOn, isTrue);
    });

    test('老版本带 vibrationOn 的数据可正常读取（未知键忽略）', () {
      final s = KeyFeedbackSettings.fromJson(const {
        'keySoundOn': false,
        'vibrationOn': true, // 历史遗留键，应被忽略而非报错
        'phaseAlertOn': true,
      });
      expect(s.keySoundOn, isFalse);
      expect(s.phaseAlertOn, isTrue);
    });
  });

  group('FeedbackPolicy.toneAssetFor', () {
    test('每个事件都有可区分的音型资产', () {
      final assets = {
        for (final e in FeedbackEvent.values) FeedbackPolicy.toneAssetFor(e),
      };
      // start/resume 共用上行音型是有意设计（恢复=重新出发），其余必须互不相同
      expect(assets.length, FeedbackEvent.values.length - 1);
      for (final e in FeedbackEvent.values) {
        expect(FeedbackPolicy.toneAssetFor(e), startsWith('assets/audio/tone_'));
        expect(FeedbackPolicy.toneAssetFor(e), endsWith('.wav'));
      }
    });
  });

  group('FeedbackPolicy.decide', () {
    test('全开时按键事件：发声', () {
      final plan =
          FeedbackPolicy.decide(KeyFeedbackSettings.defaults, FeedbackEvent.start);
      expect(plan.toneAsset, 'assets/audio/tone_start.wav');
    });

    test('关闭按键音后按键事件静默', () {
      const s = KeyFeedbackSettings(keySoundOn: false);
      final plan = FeedbackPolicy.decide(s, FeedbackEvent.skip);
      expect(plan.toneAsset, isNull);
    });

    test('阶段提醒音独立开关：关提醒不影响按键音，反之亦然', () {
      const noAlert = KeyFeedbackSettings(phaseAlertOn: false);
      expect(
        FeedbackPolicy.decide(noAlert, FeedbackEvent.phaseChange).toneAsset,
        isNull,
      );
      expect(
        FeedbackPolicy.decide(noAlert, FeedbackEvent.start).toneAsset,
        isNotNull,
      );

      const noKeySound = KeyFeedbackSettings(keySoundOn: false);
      expect(
        FeedbackPolicy.decide(noKeySound, FeedbackEvent.phaseChange).toneAsset,
        'assets/audio/tone_phase.wav',
      );
    });

    test('全关时是空计划', () {
      const s = KeyFeedbackSettings(
        keySoundOn: false,
        phaseAlertOn: false,
      );
      for (final e in FeedbackEvent.values) {
        final plan = FeedbackPolicy.decide(s, e);
        expect(plan.toneAsset, isNull, reason: '$e 不应发声');
      }
    });
  });
}
