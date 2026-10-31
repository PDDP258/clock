import 'package:ai_clock/core/timer/count_up_timer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可手动推进的假时钟。
class FakeClock {
  int nowMillis = 1000000;
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(nowMillis);
  void advance(Duration d) => nowMillis += d.inMilliseconds;
}

void main() {
  late FakeClock clock;
  late CountUpTimer timer;

  setUp(() {
    clock = FakeClock();
    timer = CountUpTimer(clock: clock.now);
  });

  group('正计时基础流程', () {
    test('初始为 idle，已计时长为 0', () {
      expect(timer.phase, CountUpPhase.idle);
      expect(timer.elapsed, Duration.zero);
      expect(timer.marks, isEmpty);
    });

    test('start 后从 0 开始累计，随时间推进增长', () {
      timer.start();
      expect(timer.phase, CountUpPhase.running);
      expect(timer.elapsed, Duration.zero);

      clock.advance(const Duration(minutes: 7));
      expect(timer.elapsed, const Duration(minutes: 7));
    });

    test('pause 冻结时长，resume 后续计，暂停期间不计时', () {
      timer.start();
      clock.advance(const Duration(minutes: 10));
      timer.pause();
      expect(timer.phase, CountUpPhase.paused);
      expect(timer.elapsed, const Duration(minutes: 10));

      // 暂停 30 分钟不应计入
      clock.advance(const Duration(minutes: 30));
      expect(timer.elapsed, const Duration(minutes: 10));

      timer.resume();
      clock.advance(const Duration(minutes: 5));
      expect(timer.elapsed, const Duration(minutes: 15));
    });

    test('finish 冻结最终时长，之后时间不再计入', () {
      timer.start();
      clock.advance(const Duration(minutes: 42));
      timer.finish();
      expect(timer.phase, CountUpPhase.finished);
      expect(timer.elapsed, const Duration(minutes: 42));

      clock.advance(const Duration(hours: 1));
      expect(timer.elapsed, const Duration(minutes: 42));
    });

    test('finished 后可重新 start，时长与打点清零', () {
      timer.start();
      clock.advance(const Duration(minutes: 20));
      timer.addMark();
      timer.finish();

      timer.start();
      expect(timer.elapsed, Duration.zero);
      expect(timer.marks, isEmpty);
    });
  });

  group('打点（正计时模式下「上一首」键语义）', () {
    test('运行中打点记录相对偏移，按时间升序', () {
      timer.start();
      clock.advance(const Duration(minutes: 5));
      expect(timer.addMark(), 0);
      clock.advance(const Duration(minutes: 13));
      expect(timer.addMark(), 1);

      expect(timer.marks,
          [const Duration(minutes: 5), const Duration(minutes: 18)]);
    });

    test('非运行态打点无效', () {
      expect(timer.addMark(), -1); // idle
      timer.start();
      timer.pause();
      expect(timer.addMark(), -1); // paused
      expect(timer.marks, isEmpty);
    });
  });

  group('持久化恢复', () {
    test('运行态序列化后恢复，死亡期间时间自动计入', () {
      timer.start();
      clock.advance(const Duration(minutes: 10));
      final json = timer.toJson();

      // 模拟进程被杀 30 分钟后重启
      clock.advance(const Duration(minutes: 30));
      final restored = CountUpTimer.fromJson(json, clock: clock.now);

      expect(restored.phase, CountUpPhase.running);
      // 正计时语义：人在工作，计时不丢 → 10 + 30 = 40 分钟
      expect(restored.elapsed, const Duration(minutes: 40));
    });

    test('暂停态序列化后恢复，时长保持冻结', () {
      timer.start();
      clock.advance(const Duration(minutes: 8));
      timer.pause();
      final json = timer.toJson();

      clock.advance(const Duration(hours: 2));
      final restored = CountUpTimer.fromJson(json, clock: clock.now);

      expect(restored.phase, CountUpPhase.paused);
      expect(restored.elapsed, const Duration(minutes: 8));
    });

    test('打点随序列化保留', () {
      timer.start();
      clock.advance(const Duration(minutes: 3));
      timer.addMark();
      clock.advance(const Duration(minutes: 9));
      timer.addMark();
      final json = timer.toJson();

      final restored = CountUpTimer.fromJson(json, clock: clock.now);
      expect(restored.marks,
          [const Duration(minutes: 3), const Duration(minutes: 12)]);
    });
  });

  group('恢复冻结 freezeForRestore（关机不计入，R11）', () {
    test('运行态恢复冻结到存活点：关机整段剔除', () {
      timer.start();
      clock.advance(const Duration(minutes: 10));
      final aliveAt = clock.nowMillis;
      final json = timer.toJson();

      // 进程被杀 30 分钟后重启
      clock.advance(const Duration(minutes: 30));
      final restored = CountUpTimer.fromJson(json, clock: clock.now);
      expect(restored.phase, CountUpPhase.running);

      expect(restored.freezeForRestore(aliveAt), isTrue);
      expect(restored.phase, CountUpPhase.paused);
      // 只计存活点前的 10 分钟，关机 30 分钟不算
      expect(restored.elapsed, const Duration(minutes: 10));
    });

    test('aliveAtMillis 为 null（旧版数据）保守计 0', () {
      timer.start();
      clock.advance(const Duration(minutes: 10));
      final json = timer.toJson();

      clock.advance(const Duration(hours: 3));
      final restored = CountUpTimer.fromJson(json, clock: clock.now);
      expect(restored.freezeForRestore(null), isTrue);

      expect(restored.phase, CountUpPhase.paused);
      expect(restored.elapsed, Duration.zero);
    });

    test('aliveAtMillis 晚于当前时间时钳到当前', () {
      timer.start();
      clock.advance(const Duration(minutes: 10));
      final future = clock.nowMillis + const Duration(hours: 5).inMilliseconds;

      expect(timer.freezeForRestore(future), isTrue);
      expect(timer.elapsed, const Duration(minutes: 10));
    });

    test('冻结后 resume 续计，关机段不含在内', () {
      timer.start();
      clock.advance(const Duration(minutes: 10));
      final aliveAt = clock.nowMillis;
      clock.advance(const Duration(hours: 2));

      timer.freezeForRestore(aliveAt);
      timer.resume();
      clock.advance(const Duration(minutes: 5));
      expect(timer.elapsed, const Duration(minutes: 15));
    });

    test('非运行态冻结无效', () {
      expect(timer.freezeForRestore(clock.nowMillis), isFalse); // idle
      timer.start();
      timer.pause();
      expect(timer.freezeForRestore(clock.nowMillis), isFalse); // paused
    });
  });
}
