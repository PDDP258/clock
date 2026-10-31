/// TimerEngine 核心用例：开始/暂停/恢复/阶段轮转/持久化恢复。
///
/// 引擎为纯 Dart，测试通过注入假时钟精确控制时间流逝。
library;

import 'package:ai_clock/core/timer/timer_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假时钟：测试手动推进。
class FakeClock {
  DateTime _now = DateTime(2024, 1, 1, 8);

  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);
}

/// 缩短版配置，让测试不用推进几十分钟。
/// autoContinue 显式为 true：本组用例测的是阶段轮转机制本身；
/// 「默认专注结束自动进休息、轮结束待继续」的语义见下方独立分组。
PomodoroConfig testConfig() => const PomodoroConfig(
      focusDuration: Duration(seconds: 100),
      shortBreakDuration: Duration(seconds: 20),
      longBreakDuration: Duration(seconds: 50),
      roundsBeforeLongBreak: 4,
      autoContinue: true,
    );

void main() {
  late FakeClock clock;
  late TimerEngine engine;

  setUp(() {
    clock = FakeClock();
    engine = TimerEngine(config: testConfig(), clock: clock.now);
  });

  test('初始为 idle，剩余时间等于一轮专注时长', () {
    expect(engine.phase, TimerPhase.idle);
    expect(engine.remaining, const Duration(seconds: 100));
  });

  test('start 进入 focusing，剩余时间随时间流逝递减', () {
    engine.start();
    expect(engine.phase, TimerPhase.focusing);

    clock.advance(const Duration(seconds: 30));
    expect(engine.remaining, const Duration(seconds: 70));
  });

  test('pause 冻结剩余时间，resume 后继续递减', () {
    engine.start();
    clock.advance(const Duration(seconds: 40));
    engine.pause();

    expect(engine.phase, TimerPhase.paused);
    expect(engine.remaining, const Duration(seconds: 60));

    // 暂停期间时间流逝不影响剩余
    clock.advance(const Duration(seconds: 10));
    expect(engine.remaining, const Duration(seconds: 60));

    engine.resume();
    expect(engine.phase, TimerPhase.focusing);
    clock.advance(const Duration(seconds: 15));
    expect(engine.remaining, const Duration(seconds: 45));
  });

  test('专注时间到 → tick 自动轮转为短休息', () {
    engine.start();
    clock.advance(const Duration(seconds: 101));
    final changed = engine.tick();

    expect(changed, isTrue);
    expect(engine.phase, TimerPhase.shortBreak);
    expect(engine.completedFocusRounds, 1);
    expect(engine.remaining, const Duration(seconds: 20));
  });

  test('休息结束自动进入下一轮专注', () {
    engine.start();
    clock.advance(const Duration(seconds: 101));
    engine.tick(); // → shortBreak
    clock.advance(const Duration(seconds: 21));
    engine.tick(); // → focusing

    expect(engine.phase, TimerPhase.focusing);
    expect(engine.remaining, const Duration(seconds: 100));
  });

  test('每 4 轮专注后进入长休息', () {
    engine.start();
    for (var round = 0; round < 3; round++) {
      clock.advance(const Duration(seconds: 101));
      engine.tick(); // → shortBreak
      clock.advance(const Duration(seconds: 21));
      engine.tick(); // → focusing
    }
    clock.advance(const Duration(seconds: 101));
    engine.tick(); // 第 4 轮结束 → longBreak

    expect(engine.completedFocusRounds, 4);
    expect(engine.phase, TimerPhase.longBreak);
    expect(engine.remaining, const Duration(seconds: 50));
  });

  test('skipPhase 跳过专注：进入短休但不计完成轮数、不计专注时长', () {
    engine.start();
    engine.skipPhase();

    expect(engine.phase, TimerPhase.shortBreak);
    expect(engine.completedFocusRounds, 0);
    expect(engine.accumulatedFocusMillis, 0);
  });

  test('skipPhase 中途跳过：只累计真实专注部分（诚实统计）', () {
    engine.start();
    clock.advance(const Duration(seconds: 40));
    engine.skipPhase();

    expect(engine.completedFocusRounds, 0);
    expect(engine.accumulatedFocusMillis, 40000);
    expect(engine.phase, TimerPhase.shortBreak);
  });

  test('暂停中跳过：按冻结剩余折算真实专注', () {
    engine.start();
    clock.advance(const Duration(seconds: 30));
    engine.pause();
    clock.advance(const Duration(minutes: 10)); // 暂停期间流逝不计
    engine.skipPhase();

    expect(engine.completedFocusRounds, 0);
    expect(engine.accumulatedFocusMillis, 30000);
  });

  test('自然完成：累计整轮并计轮数', () {
    engine.start();
    clock.advance(const Duration(seconds: 101));
    engine.tick();

    expect(engine.completedFocusRounds, 1);
    expect(engine.accumulatedFocusMillis, 100000);
  });

  test('accumulatedFocusMillis 随 JSON 持久化恢复', () {
    engine.start();
    clock.advance(const Duration(seconds: 40));
    engine.skipPhase();

    final restored = TimerEngine.fromJson(engine.toJson(), clock: clock.now);
    expect(restored.accumulatedFocusMillis, 40000);
    expect(restored.completedFocusRounds, 0);
  });

  test('addTime 增加当前阶段剩余时间', () {
    engine.start();
    engine.addTime(const Duration(seconds: 30));
    expect(engine.remaining, const Duration(seconds: 130));
  });

  test('finish 进入 completed，start 可重新开始且轮数清零', () {
    engine.start();
    clock.advance(const Duration(seconds: 101));
    engine.tick(); // rounds=1
    engine.finish();

    expect(engine.phase, TimerPhase.completed);

    engine.start();
    expect(engine.phase, TimerPhase.focusing);
    expect(engine.completedFocusRounds, 0);
    expect(engine.accumulatedFocusMillis, 0);
  });

  test('toJson/fromJson 持久化恢复：运行态恢复后剩余时间正确', () {
    engine.start();
    clock.advance(const Duration(seconds: 40));

    final json = engine.toJson();
    // 模拟杀后台 10 秒后重启
    clock.advance(const Duration(seconds: 10));
    final restored = TimerEngine.fromJson(json, clock: clock.now);

    expect(restored.phase, TimerPhase.focusing);
    expect(restored.remaining, const Duration(seconds: 50));
  });

  test('持久化恢复：死亡期间阶段已结束，恢复后 tick 自动轮转', () {
    engine.start();
    final json = engine.toJson();

    // 模拟进程死亡 120 秒（专注 100s 早已结束）
    clock.advance(const Duration(seconds: 120));
    final restored = TimerEngine.fromJson(json, clock: clock.now);

    expect(restored.phase, TimerPhase.focusing); // 恢复时状态未变
    final changed = restored.tick();
    expect(changed, isTrue);
    expect(restored.phase, TimerPhase.shortBreak); // tick 补齐轮转
  });

  test('持久化恢复：暂停态恢复后剩余时间保持冻结值', () {
    engine.start();
    clock.advance(const Duration(seconds: 30));
    engine.pause();

    final json = engine.toJson();
    clock.advance(const Duration(minutes: 5)); // 死亡 5 分钟
    final restored = TimerEngine.fromJson(json, clock: clock.now);

    expect(restored.phase, TimerPhase.paused);
    expect(restored.remaining, const Duration(seconds: 70));
  });

  // ------------------------------------------------ autoContinue=false（产品默认）
  // 真机反馈 R4 语义：一轮 = 专注 + 休息完整循环。
  //   - 专注结束 → 永远自动进休息（休息是被动的，不需要用户承诺）；
  //   - 休息结束 → 「待继续」：暂停在下一段专注起点等按键——开始专注需要
  //     用户在场承诺，否则人不在时专注空跑会记出假统计。
  //   - 跳过任何阶段（专注或休息）遵循同一规则，行为统一可预期。
  // 用户可在设置里打开自动继续。以下用例共用默认配置（autoContinue 默认 false）。
  group('autoContinue=false：专注结束自动进休息，轮结束待继续（R4 语义）', () {
    late TimerEngine manual;

    setUp(() {
      manual = TimerEngine(
        config: const PomodoroConfig(
          focusDuration: Duration(seconds: 100),
          shortBreakDuration: Duration(seconds: 20),
          longBreakDuration: Duration(seconds: 50),
          roundsBeforeLongBreak: 4,
          // autoContinue 缺省 = false
        ),
        clock: clock.now,
      );
    });

    test('专注自然结束 → 自动进短休并开始计时（不暂停）', () {
      manual.start();
      clock.advance(const Duration(seconds: 101));
      manual.tick();

      expect(manual.phase, TimerPhase.shortBreak);
      expect(manual.isRunning, isTrue);
      expect(manual.remaining, const Duration(seconds: 20)); // 短休从 tick 时刻起算整段
      expect(manual.completedFocusRounds, 1);
      expect(manual.accumulatedFocusMillis, 100000);
    });

    test('短休自然结束 → 停在下一段专注起点（待继续，冻结整轮）', () {
      manual.start();
      clock.advance(const Duration(seconds: 101));
      manual.tick(); // 专注结束 → 自动进短休
      clock.advance(const Duration(seconds: 21));
      manual.tick(); // 短休结束 → 待继续

      expect(manual.phase, TimerPhase.paused);
      expect(manual.phaseBeforePause, TimerPhase.focusing);
      expect(manual.isRunning, isFalse);
      expect(manual.remaining, const Duration(seconds: 100)); // 整轮专注冻结
    });

    test('待继续态 resume → 专注正式开始并递减', () {
      manual.start();
      clock.advance(const Duration(seconds: 101));
      manual.tick();
      clock.advance(const Duration(seconds: 21));
      manual.tick(); // → 待专注
      manual.resume();

      expect(manual.phase, TimerPhase.focusing);
      expect(manual.isRunning, isTrue);
      clock.advance(const Duration(seconds: 10));
      expect(manual.remaining, const Duration(seconds: 90));
    });

    test('跳过专注 → 自动进短休（不暂停），不计轮数、只记真实已做部分', () {
      manual.start();
      clock.advance(const Duration(seconds: 40));
      manual.skipPhase();

      expect(manual.phase, TimerPhase.shortBreak);
      expect(manual.isRunning, isTrue);
      expect(manual.completedFocusRounds, 0);
      expect(manual.accumulatedFocusMillis, 40000);
    });

    test('跳过休息 → 同样停在专注起点（轮结束统一待继续规则）', () {
      manual.start();
      clock.advance(const Duration(seconds: 101));
      manual.tick(); // 自动进短休
      clock.advance(const Duration(seconds: 5));
      manual.skipPhase(); // 跳过短休

      expect(manual.phase, TimerPhase.paused);
      expect(manual.phaseBeforePause, TimerPhase.focusing);
      expect(manual.remaining, const Duration(seconds: 100));
    });

    test('长休节奏：完成 4 轮后自动进长休运行中，长休结束才待继续', () {
      manual.start();
      for (var round = 0; round < 4; round++) {
        clock.advance(const Duration(seconds: 101));
        manual.tick(); // 专注结束 → 自动进休息
        expect(manual.isRunning, isTrue);
        if (round < 3) {
          expect(manual.phase, TimerPhase.shortBreak);
          clock.advance(const Duration(seconds: 21));
          manual.tick(); // 短休结束 → 待专注
          expect(manual.phase, TimerPhase.paused);
          manual.resume(); // 按键开始下一轮专注
        } else {
          expect(manual.phase, TimerPhase.longBreak);
          expect(manual.remaining, const Duration(seconds: 50)); // 长休整段
        }
      }
      expect(manual.completedFocusRounds, 4);

      // 长休自然结束 → 停在专注起点
      clock.advance(const Duration(seconds: 51));
      manual.tick();
      expect(manual.phase, TimerPhase.paused);
      expect(manual.phaseBeforePause, TimerPhase.focusing);
      expect(manual.remaining, const Duration(seconds: 100));
    });

    test('待继续态随 JSON 持久化恢复（杀后台后语义保持）', () {
      manual.start();
      clock.advance(const Duration(seconds: 101));
      manual.tick();
      clock.advance(const Duration(seconds: 21));
      manual.tick(); // → 待专注

      final restored = TimerEngine.fromJson(manual.toJson(), clock: clock.now);
      expect(restored.config.autoContinue, isFalse);
      expect(restored.phase, TimerPhase.paused);
      expect(restored.phaseBeforePause, TimerPhase.focusing);
      expect(restored.remaining, const Duration(seconds: 100));

      // 恢复后 resume 语义不变
      restored.resume();
      expect(restored.phase, TimerPhase.focusing);
      expect(restored.isRunning, isTrue);
    });
  });

  // ------------------------------------------------ focusSegments（专注段区间）
  group('focusSegments：记录每个专注段的实际墙钟区间', () {
    test('自然完成追加区间且边界正确', () {
      engine.start();
      final startMillis = clock.now().millisecondsSinceEpoch;
      clock.advance(const Duration(seconds: 101));
      engine.tick(); // 专注自然结束

      expect(engine.focusSegments, hasLength(1));
      final (start, end) = engine.focusSegments.single;
      expect(start, startMillis);
      expect(end - start, 100000); // 整轮专注时长
    });

    test('中途跳过追加部分区间', () {
      engine.start();
      final startMillis = clock.now().millisecondsSinceEpoch;
      clock.advance(const Duration(seconds: 40));
      engine.skipPhase();

      expect(engine.focusSegments, hasLength(1));
      final (start, end) = engine.focusSegments.single;
      expect(start, startMillis);
      expect(end - start, 40000); // 只记真实已做部分
    });

    test('JSON 往返保留区间', () {
      engine.start();
      clock.advance(const Duration(seconds: 101));
      engine.tick();

      final restored = TimerEngine.fromJson(engine.toJson(), clock: clock.now);
      expect(restored.focusSegments, engine.focusSegments);
    });

    test('finish 保留区间供结算，重新开始才清空', () {
      engine.start();
      clock.advance(const Duration(seconds: 101));
      engine.tick();
      engine.finish();

      // finish 后区间仍在（控制器需用它生成最终会话记录）
      expect(engine.focusSegments, hasLength(1));
      engine.start();
      expect(engine.focusSegments, isEmpty);
    });
  });

  // ------------------------------------------------ R9：以计时为主的诚实统计
  group('R9：段开始时间戳为真值源（addTime/暂停不被吞）', () {
    test('addTime 加时后自然完成：加时部分如实计入（旧实现被吞）', () {
      engine.start();
      clock.advance(const Duration(seconds: 100));
      engine.addTime(const Duration(seconds: 30)); // +30s → 结束推迟到 130s
      clock.advance(const Duration(seconds: 31));
      engine.tick(); // 自然完成

      expect(engine.completedFocusRounds, 1);
      expect(engine.accumulatedFocusMillis, 130000); // 100 + 30 加时
      final (start, end) = engine.focusSegments.single;
      expect(end - start, 130000);
    });

    test('addTime 后进行中已做时长不被吞：仍按段开始计算', () {
      engine.start();
      clock.advance(const Duration(seconds: 40));
      engine.addTime(const Duration(seconds: 30));

      // 旧折算 = 100 - 90 = 10s（污染）；真值 = 段开始至今 40s
      expect(engine.currentFocusDoneMillis, 40000);
    });

    test('专注中暂停：已做时长冻结，暂停期不计入', () {
      engine.start();
      clock.advance(const Duration(seconds: 40));
      engine.pause();
      clock.advance(const Duration(minutes: 10)); // 暂停期流逝

      expect(engine.currentFocusDoneMillis, 40000); // 冻结在 40s
    });

    test('含暂停的轮自然完成：墙钟 11 分钟只计 100s 实际专注', () {
      engine.start();
      clock.advance(const Duration(seconds: 40));
      engine.pause();
      clock.advance(const Duration(minutes: 10));
      engine.resume();
      clock.advance(const Duration(seconds: 61));
      engine.tick(); // 自然完成

      expect(engine.completedFocusRounds, 1);
      expect(engine.accumulatedFocusMillis, 100000); // 暂停 10min 不计
    });

    test('待继续：currentFocusDoneMillis = 0（新段未开始）', () {
      final manual = TimerEngine(
        config: const PomodoroConfig(
          focusDuration: Duration(seconds: 100),
          shortBreakDuration: Duration(seconds: 20),
          longBreakDuration: Duration(seconds: 50),
        ),
        clock: clock.now,
      );
      manual.start();
      clock.advance(const Duration(seconds: 101));
      manual.tick(); // → 短休
      clock.advance(const Duration(seconds: 21));
      manual.tick(); // → 待继续

      expect(manual.phase, TimerPhase.paused);
      expect(manual.currentFocusDoneMillis, 0);

      // resume 后新段从按键时刻起算
      manual.resume();
      clock.advance(const Duration(seconds: 15));
      expect(manual.currentFocusDoneMillis, 15000);
    });

    test('phaseStartedAtMillis 随 JSON 持久化恢复，已做时长连续', () {
      engine.start();
      clock.advance(const Duration(seconds: 40));

      final restored = TimerEngine.fromJson(engine.toJson(), clock: clock.now);
      expect(restored.currentFocusDoneMillis, 40000);

      clock.advance(const Duration(seconds: 61));
      restored.tick(); // 恢复后自然完成
      expect(restored.accumulatedFocusMillis, 100000);
    });

    test('旧版 JSON（无 phaseStartedAtMillis）回退计划折算', () {
      engine.start();
      clock.advance(const Duration(seconds: 40));
      final json = engine.toJson()..remove('phaseStartedAtMillis');

      final restored = TimerEngine.fromJson(json, clock: clock.now);
      // 回退：100 - 60 = 40s，与旧行为一致
      expect(restored.currentFocusDoneMillis, 40000);
    });
  });

  group('恢复冻结 freezeForRestore（关机不计入，R11）', () {
    test('专注中恢复冻结到存活点：关机段既不计已做也不计剩余', () {
      engine.start();
      clock.advance(const Duration(seconds: 40));
      final aliveAt = clock.now().millisecondsSinceEpoch;
      final json = engine.toJson();

      // 被杀 1 小时后重启
      clock.advance(const Duration(hours: 1));
      final restored = TimerEngine.fromJson(json, clock: clock.now);
      expect(restored.freezeForRestore(aliveAt), isTrue);

      expect(restored.phase, TimerPhase.paused);
      expect(restored.currentFocusDoneMillis, 40000); // 存活点前 40s
      expect(restored.remaining, const Duration(seconds: 60)); // 冻结剩余
    });

    test('冻结后 resume 从冻结剩余继续，关机段不补进剩余', () {
      engine.start();
      clock.advance(const Duration(seconds: 40));
      final aliveAt = clock.now().millisecondsSinceEpoch;
      clock.advance(const Duration(hours: 1));

      engine.freezeForRestore(aliveAt);
      engine.resume();
      // 继续 60s 自然完成：累计应为整轮 100s，而非被 1 小时冲垮
      clock.advance(const Duration(seconds: 61));
      engine.tick();

      expect(engine.accumulatedFocusMillis, 100000);
      expect(engine.completedFocusRounds, 1);
    });

    test('aliveAtMillis 为 null（旧版数据）保守：当前段计 0', () {
      engine.start();
      clock.advance(const Duration(seconds: 40));
      final json = engine.toJson();

      clock.advance(const Duration(hours: 5));
      final restored = TimerEngine.fromJson(json, clock: clock.now);
      expect(restored.freezeForRestore(null), isTrue);

      expect(restored.phase, TimerPhase.paused);
      expect(restored.currentFocusDoneMillis, 0);
    });

    test('非运行态冻结无效（已暂停 / 空闲）', () {
      expect(engine.freezeForRestore(clock.now().millisecondsSinceEpoch),
          isFalse); // idle
      engine.start();
      engine.pause();
      expect(engine.freezeForRestore(clock.now().millisecondsSinceEpoch),
          isFalse); // paused
    });
  });
}
