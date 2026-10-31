/// AI 预设问答单测（看板 #50/#51，应用层接缝）。
///
/// 语义要点：
/// - 未开启/未同意/无 Key → ask 静默短路，零请求；
/// - 周报题：成功 → Ready 文本 + 写 `w:周键:题id` 缓存；同周同题走缓存；
///   「换一句」force 跳缓存真请求；
/// - 当日题：数据走 dailySummaryProvider，缓存键 `d:yyyy-MM-dd:题id`，
///   不同查看日各自缓存；
/// - LLM 失败/空回复 → 静默回 Idle，不抛穿；
/// - 上传快照带 type（ask_week/ask_day）与问题文本。
library;

import 'dart:convert';
import 'dart:io';

import 'package:ai_clock/core/ai/ai_prompt.dart';
import 'package:ai_clock/core/ai/llm_provider.dart';
import 'package:ai_clock/core/ai/memory_log.dart';
import 'package:ai_clock/core/insight/insight.dart';
import 'package:ai_clock/features/ai/application/ai_ask.dart';
import 'package:ai_clock/features/ai/application/ai_controller.dart';
import 'package:ai_clock/features/ai/application/ai_memory.dart';
import 'package:ai_clock/features/stats/application/stats_controller.dart';
import 'package:ai_clock/features/stats/domain/daily_summary.dart';
import 'package:ai_clock/features/stats/domain/weekly_report.dart';
import 'package:ai_clock/platform/files/memory_log_store.dart';
import 'package:ai_clock/platform/prefs/prefs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 计数假 LLM：记录请求次数，按脚本返回/抛错。
class FakeLlm implements LlmProvider {
  FakeLlm({this.text, this.failure});
  String? text;
  LlmFailure? failure;
  var calls = 0;

  /// 最近一次收到的提示词（断言 system / token 预算用）
  AiPrompt? lastPrompt;

  @override
  String get id => 'fake';

  @override
  Future<String?> generateInsight(AiPrompt prompt) async {
    calls++;
    lastPrompt = prompt;
    if (failure != null) throw failure!;
    return text;
  }

  @override
  Future<bool> ping() async => true;
}

void main() {
  const fakeInsight = WeeklyInsight(
    thisWeekMinutes: 620,
    lastWeekMinutes: 540,
    changeRatio: 0.148,
    sessionCount: 21,
    rounds: 17,
    slotDistribution: {},
    bestSlot: null,
    streakDays: 5,
    bufferUsed: 1,
    interruptionCount: 6,
    interruptionMinutes: 32,
    interruptionSlotDistribution: {
      DaySlot.evening: 0.67,
      DaySlot.afternoon: 0.33,
    },
    interruptionRatio: 0.052,
    avgInterruptionMinutes: 5,
    longestSegmentMinutes: 50,
    longestSegmentSlot: DaySlot.afternoon,
    bestDayWeekday: 3,
    bestDayMinutes: 240,
    activeDays: 3,
    daysElapsed: 3,
  );

  const fakeSummary = DailySummary(
    focusMillis: 95 * 60000,
    rounds: 4,
    sessionCount: 3,
    interruptionCount: 2,
    interruptionMillis: 300000,
    bestSlot: DaySlot.afternoon,
    firstStartMillis: null,
    lastEndMillis: null,
    longestSegmentMillis: 50 * 60000,
  );

  late SharedPreferences prefs;
  late FakeLlm fakeLlm;

  late Directory memoryDir;

  ProviderContainer container() => ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        weeklyInsightProvider.overrideWith((ref) async => fakeInsight),
        dailySummaryProvider.overrideWith((ref, day) async => fakeSummary),
        // 记忆日志落到临时目录：单测无平台通道，不能走 path_provider
        aiMemoryLogStoreProvider.overrideWithValue(
            AiMemoryLogStore(directory: () async => memoryDir)),
        llmProviderFactoryProvider
            .overrideWithValue((vendor, apiKey) => fakeLlm),
      ]);

  Future<void> enableAll(ProviderContainer c) async {
    await c.read(aiSettingsProvider.notifier).enableWithConsent();
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fakeLlm = FakeLlm(text: '下午占比最高，把难事放到下午。');
    memoryDir = Directory.systemTemp.createTempSync('ai_memory_ask');
  });

  tearDown(() {
    if (memoryDir.existsSync()) memoryDir.deleteSync(recursive: true);
  });

  test('buildAskPrompt：白名单数字 + 问题 + 字数约束 + 200 tokens 预算', () {
    final p = buildAskPrompt(fakeInsight, aiAskWeeklyQuestions[0]);
    expect(p.user, contains('620 分钟'));
    expect(p.user, contains('540 分钟'));
    expect(p.user, contains(aiAskWeeklyQuestions[0].label));
    expect(p.user, contains('不超过 80 字'));
    // 事实块与周报解读同源（08-B2）
    expect(p.user, contains('部分周'));
    expect(p.system, contains('不得自行计算'));
    // 80 字契约不需要 600 tokens（08-A4）
    expect(p.maxTokens, kAskMaxTokens);
  });

  test('buildDailyAskPrompt：当日白名单数字 + 问题', () {
    final p =
        buildDailyAskPrompt(fakeSummary, aiAskDailyQuestions[0]);
    expect(p.user, contains('95 分钟'));
    expect(p.user, contains('分 3 段'));
    expect(p.user, contains('最长一段：50 分钟'));
    expect(p.user, contains('下午'));
    expect(p.user, contains(aiAskDailyQuestions[0].label));
    expect(p.user, contains('不超过 80 字'));
    expect(p.maxTokens, kAskMaxTokens);
    // 事实块与当日点评同源（08-B2）
    expect(p.user, contains('4 个番茄'));
  });

  test('parseAskAnswer：首个有意义的行、去前缀、超长截断', () {
    expect(parseAskAnswer('\n答：下午最好。'), '下午最好。');
    expect(parseAskAnswer('  \n\n直接回答'), '直接回答');
    expect(parseAskAnswer('答：'), isNull);
    expect(parseAskAnswer('   \n  '), isNull);
    final long = '长' * 130;
    expect(parseAskAnswer(long)!.length, 121); // 120 + 省略号
  });

  test('parseAskAnswer 加固：跳过模型寒暄与 Markdown 装饰（08-A3）', () {
    // 先寒暄一句，用户不该只看到这句废话
    expect(parseAskAnswer('好的，根据你的数据：\n下午的占比最高。'), '下午的占比最高。');
    // 加粗 + 列表前缀
    expect(parseAskAnswer('**答：**下午最好。'), '下午最好。');
    expect(parseAskAnswer('- 答：下午最好。'), '下午最好。');
    // 只有寒暄、没有实质答案 → null（静默，不展示半截乱文）
    expect(parseAskAnswer('好的，根据你的数据：'), isNull);
  });

  test('AI 未开启：静默短路，零请求、状态不动', () async {
    final c = container();
    await c.read(aiAskProvider.notifier).ask(aiAskWeeklyQuestions[0]);
    expect(fakeLlm.calls, 0);
    expect(c.read(aiAskProvider).text, isNull);
    expect(c.read(aiAskProvider).loading, isFalse);
  });

  test('开启但无 Key：静默短路，零请求', () async {
    final c = container();
    await c.read(aiSettingsProvider.notifier).enableWithConsent();
    await c.read(aiAskProvider.notifier).ask(aiAskWeeklyQuestions[0]);
    expect(fakeLlm.calls, 0);
  });

  test('周报题成功：Ready + 缓存 + 快照 type=ask_week；同题走缓存', () async {
    final c = container();
    await enableAll(c);
    await c.read(aiAskProvider.notifier).ask(aiAskWeeklyQuestions[0]);

    final s = c.read(aiAskProvider);
    expect(s.text, '下午占比最高，把难事放到下午。');
    expect(s.qid, 'best_slot');
    expect(s.loading, isFalse);
    expect(fakeLlm.calls, 1);

    final upload =
        (jsonDecode(prefs.getString('ai_last_upload_json')!) as Map)
            .cast<String, dynamic>();
    expect(upload['type'], 'ask_week');
    expect(upload['question'], '我什么时段最专注？');
    expect(upload['week_focus_minutes'], 620);

    await c.read(aiAskProvider.notifier).ask(aiAskWeeklyQuestions[0]);
    expect(fakeLlm.calls, 1);
  });

  test('换一句（force）：跳过缓存真请求', () async {
    final c = container();
    await enableAll(c);
    await c.read(aiAskProvider.notifier).ask(aiAskWeeklyQuestions[0]);
    await c
        .read(aiAskProvider.notifier)
        .ask(aiAskWeeklyQuestions[0], force: true);
    expect(fakeLlm.calls, 2);
  });

  test('不同题各自缓存：两题各请求一次，重复点同题不再请求', () async {
    final c = container();
    await enableAll(c);
    await c.read(aiAskProvider.notifier).ask(aiAskWeeklyQuestions[0]);
    await c.read(aiAskProvider.notifier).ask(aiAskWeeklyQuestions[2]);
    expect(fakeLlm.calls, 2);
    await c.read(aiAskProvider.notifier).ask(aiAskWeeklyQuestions[0]);
    expect(fakeLlm.calls, 2);
  });

  test('当日题：走 dailySummary 数据源，快照 type=ask_day 带日期', () async {
    final c = container();
    await enableAll(c);
    final day = DateTime(2026, 9, 12);
    await c.read(aiAskProvider.notifier).ask(aiAskDailyQuestions[0], day: day);

    expect(fakeLlm.calls, 1);
    expect(c.read(aiAskProvider).text, '下午占比最高，把难事放到下午。');
    final upload =
        (jsonDecode(prefs.getString('ai_last_upload_json')!) as Map)
            .cast<String, dynamic>();
    expect(upload['type'], 'ask_day');
    expect(upload['date'], '2026-09-12');
    expect(upload['focus_minutes'], 95);
  });

  test('当日题按日缓存：不同日各请求一次，同日同题走缓存', () async {
    final c = container();
    await enableAll(c);
    await c
        .read(aiAskProvider.notifier)
        .ask(aiAskDailyQuestions[0], day: DateTime(2026, 9, 12));
    await c
        .read(aiAskProvider.notifier)
        .ask(aiAskDailyQuestions[0], day: DateTime(2026, 9, 11));
    expect(fakeLlm.calls, 2);
    await c
        .read(aiAskProvider.notifier)
        .ask(aiAskDailyQuestions[0], day: DateTime(2026, 9, 12));
    expect(fakeLlm.calls, 2);
  });

  test('记忆日志（#54）：问当下注入近 7 日记忆，问历史某天不注入', () async {
    final c = container();
    await enableAll(c);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await c.read(aiMemoryLogStoreProvider).upsert(AiMemoryEntry(
          date: memoryDateKey(yesterday),
          updatedAt: isoLocalWithOffset(yesterday),
          facts: const <String, Object?>{'focus_minutes': 40},
          extra: const <String, Object?>{'memory': '昨天的记忆标记'},
        ));

    // 周报题 = 问当下 → 注入
    await c.read(aiAskProvider.notifier).ask(aiAskWeeklyQuestions[0]);
    expect(fakeLlm.lastPrompt!.user, contains(kMemoryBlockHeader));
    expect(fakeLlm.lastPrompt!.user, contains('昨天的记忆标记'));

    // 当日题 + 今天 → 注入
    await c
        .read(aiAskProvider.notifier)
        .ask(aiAskDailyQuestions[0], day: DateTime.now(), force: true);
    expect(fakeLlm.lastPrompt!.user, contains(kMemoryBlockHeader));

    // 当日题 + 历史某天 → 不注入（那天的数字就是事实块本身）
    await c.read(aiAskProvider.notifier).ask(aiAskDailyQuestions[0],
        day: DateTime.now().subtract(const Duration(days: 5)), force: true);
    expect(fakeLlm.lastPrompt!.user, isNot(contains(kMemoryBlockHeader)));
  });

  test('LLM 失败：静默回 Idle，不抛穿', () async {
    final c = container();
    await enableAll(c);
    fakeLlm.failure = const LlmFailure(LlmFailureKind.network, 'offline');
    await c.read(aiAskProvider.notifier).ask(aiAskWeeklyQuestions[0]);
    final s = c.read(aiAskProvider);
    expect(s.text, isNull);
    expect(s.loading, isFalse);
  });
}
