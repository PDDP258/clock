/// 自定义提示音：钳制规则与持久化编解码（2026-10-05）。
library;

import 'package:ai_clock/core/feedback/custom_tone.dart';
import 'package:ai_clock/platform/audio/audio_tools_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toneClampDuration', () {
    test('区间钳制', () {
      expect(toneClampDuration(50), kToneMinMs);
      expect(toneClampDuration(3200), 3200);
      expect(toneClampDuration(9999), kToneMaxMs);
    });
  });

  group('toneClampStart', () {
    test('起点不越过音频末尾（保持长度，挪起点）', () {
      // 2 分钟音频、5s 片段：起点最多到 119.5s
      expect(toneClampStart(118_000, 5000, 120_000), 118_000);
      expect(toneClampStart(119_000, 5000, 120_000), 115_000);
      expect(toneClampStart(500_000, 5000, 120_000), 115_000);
    });
    test('负起点与短音频', () {
      expect(toneClampStart(-100, 3000, 120_000), 0);
      expect(toneClampStart(1000, 5000, 3000), 0); // 音频比片段还短
      expect(toneClampStart(1000, 3000, 0), 0); // 时长探测失败
    });
  });

  group('ToneCustom 编解码', () {
    test('JSON 往返', () {
      const tone = ToneCustom(
        path: '/x/tones/t_ab12cd34.mp3',
        name: '夜曲.mp3',
        startMs: 61_500,
        durationMs: 3200,
        trackMs: 120_000,
      );
      final back =
          ToneCustom.fromJson(tone.toJson().cast<Object?, Object?>());
      expect(back, isNotNull);
      expect(back!.path, tone.path);
      expect(back.name, tone.name);
      expect(back.startMs, tone.startMs);
      expect(back.durationMs, tone.durationMs);
      expect(back.trackMs, tone.trackMs);
    });

    test('坏数据不抛（返回 null / 空表）', () {
      expect(ToneCustom.fromJson(<Object?, Object?>{}), isNull);
      expect(ToneCustom.fromJson(<Object?, Object?>{'path': ''}), isNull);
      expect(toneMapDecode('not json'), isEmpty);
      expect(toneMapDecode(null), isEmpty);
    });

    group('toneMapEncode/Decode 往返 + 单条损坏隔离', () {
      test('往返', () {
        final tones = <String, ToneCustom>{
          'assets/audio/tone_start.wav': const ToneCustom(
              path: '/a.mp3', name: 'a', startMs: 0, durationMs: 2000, trackMs: 10_000),
          'assets/audio/tone_phase.wav': const ToneCustom(
              path: '/b.mp3', name: 'b', startMs: 500, durationMs: 1500, trackMs: 9000),
        };
        final back = toneMapDecode(toneMapEncode(tones));
        expect(back.length, 2);
        expect(back['assets/audio/tone_start.wav']!.durationMs, 2000);
        expect(back['assets/audio/tone_phase.wav']!.startMs, 500);
      });
    });
  });

  group('toneCustomFromPick', () {
    test('默认从 0 开始，长度钳到 5s', () {
      final tone = toneCustomFromPick(const PickedAudio(
          path: '/x.mp3', name: 'x.mp3', durationMs: 120_000));
      expect(tone.startMs, 0);
      expect(tone.durationMs, kToneMaxMs);
      expect(tone.trackMs, 120_000);
    });
    test('短音频：片段=全长', () {
      final tone = toneCustomFromPick(const PickedAudio(
          path: '/y.wav', name: 'y.wav', durationMs: 800));
      expect(tone.durationMs, 800);
    });
  });

  group('kToneSlots', () {
    test('7 个槽位，键唯一', () {
      expect(kToneSlots.length, 7);
      expect(kToneSlots.keys.toSet().length, 7);
    });
  });
}
