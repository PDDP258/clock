/// AiController 单测（V0.5：开关/同意/缓存/降级矩阵的应用层接缝）。
///
/// 语义要点（AI 安静原则与降级矩阵的代码化）：
/// - 总开关关闭/未同意/未配置 Key → requestInterpretation 直接降级，
///   **零网络请求**（假 provider 计数断言）；
/// - 成功路径写缓存，同周第二次调用走缓存不再请求（US-AI-A05）；
/// - LLM 失败/乱文 → 对应降级原因，不抛穿；
/// - deleteAiData 清空缓存/同意/上传快照（US-AI-D04）；
/// - 记忆日志（看板 #54）：近 7 日注入请求、成功后落盘当日条目（同日一条）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:ai_clock/core/ai/ai_prompt.dart';
import 'package:ai_clock/core/ai/llm_provider.dart';
import 'package:ai_clock/core/ai/memory_log.dart';
import 'package:ai_clock/core/insight/insight.dart';
import 'package:ai_clock/core/insight/insight_engine.dart';
import 'package:ai_clock/features/ai/application/ai_controller.dart';
import 'package:ai_clock/features/ai/application/ai_memory.dart';
import 'package:ai_clock/features/stats/application/stats_controller.dart';
import 'package:ai_clock/features/stats/domain/daily_summary.dart';
import 'package:ai_clock/features/stats/domain/weekly_report.dart'
    show DaySlot;
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

  /// 数据量不足的洞察（08-A6 门槛：< 60 分钟且 < 3 次会话）
  const thinInsight = WeeklyInsight(
    thisWeekMinutes: 25,
    lastWeekMinutes: 0,
    changeRatio: null,
    sessionCount: 1,
    rounds: 1,
    slotDistribution: {},
    bestSlot: null,
    streakDays: 1,
    bufferUsed: 0,
    interruptionCount: 0,
    interruptionMinutes: 0,
    interruptionSlotDistribution: {},
    interruptionRatio: null,
    avgInterruptionMinutes: 0,
    longestSegmentMinutes: 25,
    longestSegmentSlot: null,
    bestDayWeekday: 1,
    bestDayMinutes: 25,
    activeDays: 1,
    daysElapsed: 1,
  );

  const okText = '本周专注 620 分钟。\n\n建议：继续保持。';

  /// 记忆日志用的当日小结（saveToday 的 facts 来源）
  const daySummary = DailySummary(
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

  /// 当前供 weeklyInsightProvider 返回的洞察（A2 指纹测试里会被改动）
  late WeeklyInsight servedInsight;

  ProviderContainer container() => ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        weeklyInsightProvider.overrideWith((ref) async => servedInsight),
        // 记忆落盘要读当日小结；单测里给固定值
        dailySummaryProvider.overrideWith((ref, day) async => daySummary),
        // 记忆日志落到临时目录：单测无平台通道，不能走 path_provider
        aiMemoryLogStoreProvider.overrideWithValue(
            AiMemoryLogStore(directory: () async => memoryDir)),
        llmProviderFactoryProvider
            .overrideWithValue((vendor, apiKey) => fakeLlm),
      ]);

  /// 开启总开关并同意（经 notifier 正式路径）。
  Future<void> enableWithConsent(ProviderContainer c) =>
      c.read(aiSettingsProvider.notifier).enableWithConsent();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fakeLlm = FakeLlm(text: okText);
    servedInsight = fakeInsight;
    memoryDir = Directory.systemTemp.createTempSync('ai_memory_ctrl');
  });

  tearDown(() {
    if (memoryDir.existsSync()) memoryDir.deleteSync(recursive: true);
  });

  test('默认全关：总开关 false、无同意记录', () {
    final c = container();
    expect(c.read(aiSettingsProvider).enabled, isFalse);
    expect(c.read(aiSettingsProvider).hasConsent, isFalse);
  });

  test('总开关关闭：requestInterpretation 降级 disabled 且零请求', () async {
    final c = container();
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    final s = c.read(aiInsightControllerProvider);
    expect(s, isA<AiInsightDegraded>());
    expect((s as AiInsightDegraded).reason, AiDegradeReason.disabled);
    expect(fakeLlm.calls, 0);
  });

  test('已开启未配置 Key：降级 noKey 且零请求', () async {
    final c = container();
    await enableWithConsent(c);
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    final s = c.read(aiInsightControllerProvider);
    expect((s as AiInsightDegraded).reason, AiDegradeReason.noKey);
    expect(fakeLlm.calls, 0);
  });

  test('成功：ready + 写缓存 + 记录上传快照；同周二次调用走缓存', () async {
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();

    final s = c.read(aiInsightControllerProvider);
    expect(s, isA<AiInsightReady>());
    expect((s as AiInsightReady).value.suggestion, '继续保持。');
    expect(s.fromCache, isFalse);
    expect(fakeLlm.calls, 1);
    // US-AI-A04：上传快照已记录（白名单 JSON）
    expect(prefs.getString('ai_last_upload_json'), contains('620'));

    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    final s2 = c.read(aiInsightControllerProvider);
    expect((s2 as AiInsightReady).fromCache, isTrue);
    expect(fakeLlm.calls, 1); // 缓存命中，不再请求
  });

  test('记忆日志（#54）：成功后落盘当日条目，同日只留一条且 rev 递增', () async {
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();

    final store = c.read(aiMemoryLogStoreProvider);
    final file = await store.read();
    expect(file.entries, hasLength(1));
    final e = file.entries.single;
    expect(e.date, memoryDateKey(DateTime.now()));
    expect(e.promptVersion, kPromptVersion);
    expect(e.rev, 1);
    expect(e.insight, contains('建议：')); // 存压平后的单行形态
    expect(e.insight, isNot(contains('\n')));
    expect(e.facts!['sessions'], 3); // 当日白名单数字来自 dailySummary

    // 强制再解读一次：同一天仍是同一条，rev +1（覆盖当日，不追加新条）
    await c
        .read(aiInsightControllerProvider.notifier)
        .requestInterpretation(force: true);
    final again = await store.read();
    expect(again.entries, hasLength(1));
    expect(again.entries.single.rev, 2);
  });

  test('记忆日志（#54）：近 7 日注入请求，夹在事实块与任务之间', () async {
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');

    // 预置一条昨天的条目：本机数字 + 外部程序写入的 memory
    final store = c.read(aiMemoryLogStoreProvider);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await store.upsert(AiMemoryEntry(
      date: memoryDateKey(yesterday),
      updatedAt: isoLocalWithOffset(yesterday),
      facts: const <String, Object?>{'focus_minutes': 40, 'sessions': 2},
      extra: const <String, Object?>{'memory': '昨天在赶论文'},
    ));

    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    final user = fakeLlm.lastPrompt!.user;
    expect(user, contains(kMemoryBlockHeader));
    expect(user, contains('昨天在赶论文'));
    expect(user, contains('专注 40 分钟'));
    // 位置：事实块 → 记忆 → 任务（任务指令留在末尾，遵循度最高）
    final memoryAt = user.indexOf(kMemoryBlockHeader);
    expect(memoryAt, greaterThan(user.indexOf('本周专注')));
    expect(user.indexOf('请输出：'), greaterThan(memoryAt));
    // 记忆也是发出去的内容：上传快照如实记录（US-AI-A04）
    final upload =
        jsonDecode(prefs.getString('ai_last_upload_json')!) as Map<String, dynamic>;
    expect(upload['memory_block'], contains('昨天在赶论文'));
  });

  test('LLM 超时：降级 timeout，不抛穿', () async {
    fakeLlm = FakeLlm(
        failure: const LlmFailure(LlmFailureKind.timeout, 'deepseek'));
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    final s = c.read(aiInsightControllerProvider);
    expect((s as AiInsightDegraded).reason, AiDegradeReason.timeout);
  });

  test('LLM 返回乱文（解析失败）：降级 badResponse', () async {
    fakeLlm = FakeLlm(text: '没有建议段的回复');
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    final s = c.read(aiInsightControllerProvider);
    expect((s as AiInsightDegraded).reason, AiDegradeReason.badResponse);
  });

  test('deleteAiData：清缓存/同意/快照并关闭总开关', () async {
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    expect(fakeLlm.calls, 1);

    await c.read(aiSettingsProvider.notifier).deleteAiData();
    expect(c.read(aiSettingsProvider).enabled, isFalse);
    expect(c.read(aiSettingsProvider).hasConsent, isFalse);
    expect(prefs.getString('ai_insight_cache'), isNull);
    expect(prefs.getString('ai_last_upload_json'), isNull);

    // 删除后再次请求：降级 disabled 零请求
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    expect(fakeLlm.calls, 1);
  });

  test('force=true 跳过同周缓存强制重新请求（「重新解读」按钮）', () async {
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    expect(fakeLlm.calls, 1);
    await c
        .read(aiInsightControllerProvider.notifier)
        .requestInterpretation(force: true);
    expect(fakeLlm.calls, 2);
    expect((c.read(aiInsightControllerProvider) as AiInsightReady).fromCache,
        isFalse);
  });

  test('autoInterpretIfDue：未开启/无 Key/本周已缓存全静默短路（零请求且状态不变）',
      () async {
    // 未开启
    final c = container();
    await c.read(aiInsightControllerProvider.notifier).autoInterpretIfDue();
    expect(fakeLlm.calls, 0);
    expect(c.read(aiInsightControllerProvider), isA<AiInsightIdle>());

    // 已开启但无 Key
    await enableWithConsent(c);
    await c.read(aiInsightControllerProvider.notifier).autoInterpretIfDue();
    expect(fakeLlm.calls, 0);
    expect(c.read(aiInsightControllerProvider), isA<AiInsightIdle>());

    // 配 Key 后本周首次：自动请求成功并缓存
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiInsightControllerProvider.notifier).autoInterpretIfDue();
    expect(fakeLlm.calls, 1);
    expect(c.read(aiInsightControllerProvider), isA<AiInsightReady>());

    // 本周已有缓存：再次到期检查静默短路
    await c.read(aiInsightControllerProvider.notifier).autoInterpretIfDue();
    expect(fakeLlm.calls, 1);
  });

  // ------------------------------------------------ 08-A4/A5：提示词分档

  test('请求携带 system 硬约束、周报 600 tokens 预算（08-A4/A5）', () async {
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();

    final prompt = fakeLlm.lastPrompt!;
    expect(prompt.maxTokens, kWeeklyMaxTokens);
    expect(prompt.system, isNotNull);
    // 三条关键硬约束都在 system 里（而不是散在 user 正文）
    expect(prompt.system, contains('原样引用'));
    expect(prompt.system, contains('加油'));
    expect(prompt.system, contains('不得自行计算'));
    // 部分周如实声明（08-A1）：不允许 LLM 把半周数据当整周判断
    expect(prompt.user, contains('进行中的部分周'));
    expect(prompt.user, contains('本周进度'));
  });

  // ------------------------------------------------ 08-A6：数据量门槛

  test('本周数据不足：降级 insufficientData 且零请求（08-A6）', () async {
    servedInsight = thinInsight;
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();

    final s = c.read(aiInsightControllerProvider);
    expect((s as AiInsightDegraded).reason, AiDegradeReason.insufficientData);
    expect(fakeLlm.calls, 0);
    // 没发请求就不该留下上传快照
    expect(prefs.getString('ai_last_upload_json'), isNull);
  });

  test('数据量门槛边界：够 60 分钟即放行', () async {
    servedInsight = const WeeklyInsight(
      thisWeekMinutes: 60,
      lastWeekMinutes: 50,
      changeRatio: 0.2,
      sessionCount: 1,
      rounds: 1,
      slotDistribution: {},
      bestSlot: null,
      streakDays: 1,
      bufferUsed: 0,
      interruptionCount: 0,
      interruptionMinutes: 0,
      interruptionSlotDistribution: {},
      interruptionRatio: null,
      avgInterruptionMinutes: 0,
      longestSegmentMinutes: 60,
      longestSegmentSlot: null,
      bestDayWeekday: 2,
      bestDayMinutes: 60,
      activeDays: 1,
      daysElapsed: 2,
    );
    expect(servedInsight.isSufficient, isTrue);
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    expect(fakeLlm.calls, 1);
  });

  test('autoInterpretIfDue 数据不足：静默短路，不置降级态（08-A6）', () async {
    servedInsight = thinInsight;
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiInsightControllerProvider.notifier).autoInterpretIfDue();
    expect(fakeLlm.calls, 0);
    expect(c.read(aiInsightControllerProvider), isA<AiInsightIdle>());
  });

  // ------------------------------------------------ 08-A2：缓存数据指纹

  test('同周缓存命中且数据未变：dataUpdated=false（08-A2）', () async {
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    expect(fakeLlm.calls, 1);

    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    final s = c.read(aiInsightControllerProvider) as AiInsightReady;
    expect(s.fromCache, isTrue);
    expect(s.dataUpdated, isFalse);
    expect(fakeLlm.calls, 1);
  });

  test('本周数据已变化：缓存仍回看但标 dataUpdated，且不自动重发（08-A2）',
      () async {
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    expect(fakeLlm.calls, 1);

    // 本周又专注了：分钟数与会话数都涨
    servedInsight = const WeeklyInsight(
      thisWeekMinutes: 780,
      lastWeekMinutes: 540,
      changeRatio: 0.44,
      sessionCount: 26,
      rounds: 21,
      slotDistribution: {},
      bestSlot: null,
      streakDays: 6,
      bufferUsed: 1,
      interruptionCount: 7,
      interruptionMinutes: 35,
      interruptionSlotDistribution: {DaySlot.evening: 1.0},
      interruptionRatio: 0.045,
      avgInterruptionMinutes: 5,
      longestSegmentMinutes: 55,
      longestSegmentSlot: null,
      bestDayWeekday: 4,
      bestDayMinutes: 300,
      activeDays: 4,
      daysElapsed: 4,
    );
    // 生产环境由 focus_controller._invalidateStats() 的失效级联完成
    // （streakProvider → weeklyInsightProvider）；测试里直接失效模拟
    c.invalidate(weeklyInsightProvider);

    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    final s = c.read(aiInsightControllerProvider) as AiInsightReady;
    expect(s.fromCache, isTrue);
    expect(s.dataUpdated, isTrue);
    // 安静原则：只提示，不自动重发
    expect(fakeLlm.calls, 1);

    // 用户主动点「重新解读」才真请求
    await c
        .read(aiInsightControllerProvider.notifier)
        .requestInterpretation(force: true);
    expect(fakeLlm.calls, 2);
    expect(
        (c.read(aiInsightControllerProvider) as AiInsightReady).dataUpdated,
        isFalse);
  });

  // ------------------------------------------------ 看板 #53：口径版本
  //   改了提示词后，用户手里的旧解读必须能被提示刷新，否则「改了看不出变化」

  test('旧口径缓存（fp 无提示词版本）：回看但标 dataUpdated，零重发', () async {
    final c = container();
    await enableWithConsent(c);
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    // 模拟 v1 时期写入的缓存：fp 只有数据指纹，没有 @提示词版本
    await prefs.setString(
        'ai_insight_cache',
        jsonEncode(<String, String>{
          'week': isoWeekKey(DateTime.now()),
          'text': '本周专注 620 分钟。\n\n建议：继续保持。',
          'fp': servedInsight.dataFingerprint,
        }));

    await c.read(aiInsightControllerProvider.notifier).requestInterpretation();
    final s = c.read(aiInsightControllerProvider) as AiInsightReady;
    expect(s.fromCache, isTrue);
    expect(s.dataUpdated, isTrue, reason: '提示词版本变了，旧解读应提示刷新');
    expect(fakeLlm.calls, 0, reason: '安静原则：只给被动提示，不自动重发');
  });
}
