/// AI 当日点评单测（看板 #46）：提示词白名单、解析容错、
/// 控制器按日缓存/静默短路（零请求断言）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:ai_clock/core/ai/ai_prompt.dart';
import 'package:ai_clock/core/ai/llm_provider.dart';
import 'package:ai_clock/core/ai/memory_log.dart';
import 'package:ai_clock/features/ai/application/ai_controller.dart';
import 'package:ai_clock/features/ai/application/ai_memory.dart';
import 'package:ai_clock/features/ai/application/daily_comment.dart';
import 'package:ai_clock/features/stats/application/stats_controller.dart';
import 'package:ai_clock/features/stats/domain/daily_summary.dart';
import 'package:ai_clock/features/stats/domain/weekly_report.dart';
import 'package:ai_clock/platform/files/memory_log_store.dart';
import 'package:ai_clock/platform/prefs/prefs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 计数假 LLM。
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

  /// 当前供 dailySummaryProvider 返回的小结（A2 指纹测试里会被改动）
  late DailySummary servedSummary;

  ProviderContainer container() => ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dailySummaryProvider.overrideWith((ref, day) async => servedSummary),
        // 记忆日志落到临时目录：单测无平台通道，不能走 path_provider
        aiMemoryLogStoreProvider.overrideWithValue(
            AiMemoryLogStore(directory: () async => memoryDir)),
        llmProviderFactoryProvider
            .overrideWithValue((vendor, apiKey) => fakeLlm),
      ]);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fakeLlm = FakeLlm(text: '今天节奏不错，下午状态最好。');
    servedSummary = fakeSummary;
    memoryDir = Directory.systemTemp.createTempSync('ai_memory_daily');
  });

  tearDown(() {
    if (memoryDir.existsSync()) memoryDir.deleteSync(recursive: true);
  });

  test('buildDailyPrompt：白名单数字原样出现 + system 防编造 + 120 tokens', () {
    final p = buildDailyPrompt(fakeSummary);
    expect(p.user, contains('95 分钟'));
    expect(p.user, contains('4 个番茄'));
    expect(p.user, contains('下午'));
    // 约束在 system（08-A5），token 预算按 40 字契约收到 120（08-A4）
    expect(p.system, contains('编造'));
    expect(p.maxTokens, kDailyMaxTokens);
  });

  test('parseDailyComment：取首个有意义的行、去前缀', () {
    expect(parseDailyComment('\n\n点评：稳。\n其他'), '稳。');
    expect(parseDailyComment('  '), isNull);
  });

  test('parseDailyComment 加固：跳过寒暄与 Markdown（08-A3）', () {
    expect(parseDailyComment('好的，以下是点评：\n今天节奏稳。'), '今天节奏稳。');
    expect(parseDailyComment('**点评：** 节奏稳。'), '节奏稳。');
  });

  test('parseDailyComment：超长截断 80 字', () {
    final long = '好' * 100;
    expect(parseDailyComment(long)!.length, 81); // 80 + 省略号
  });

  test('当日点评复用当日事实块单一来源（08-B2）', () {
    expect(dailyFactsBlock(fakeSummary), contains('最长一段：50 分钟'));
  });

  test('当日事实块不含钟点（07 §5.1 承诺：起止明细永不外发）', () {
    const withTimes = DailySummary(
      focusMillis: 95 * 60000,
      rounds: 4,
      sessionCount: 3,
      interruptionCount: 2,
      interruptionMillis: 300000,
      bestSlot: DaySlot.afternoon,
      firstStartMillis: 9 * 3600 * 1000 + 12 * 60000, // 09:12
      lastEndMillis: 18 * 3600 * 1000 + 40 * 60000, // 18:40
      longestSegmentMillis: 50 * 60000,
    );
    // 事实块（进 prompt）与上传快照（进网络）都不含 HH:mm
    final block = dailyFactsBlock(withTimes);
    expect(block, isNot(contains('起止')));
    expect(RegExp(r'\d{1,2}:\d{2}').hasMatch(block), isFalse);
    final upload = dailyFactsJson(withTimes);
    expect(upload.keys, isNot(contains('first_start')));
    expect(upload.keys, isNot(contains('last_end')));
    expect(RegExp(r'\d{1,2}:\d{2}').hasMatch(jsonEncode(upload)), isFalse);
  });

  test('AI 未开启：请求静默短路（零请求、保持 Idle）', () async {
    final c = container();
    await c
        .read(aiDailyCommentProvider.notifier)
        .requestDailyComment();
    expect(fakeLlm.calls, 0);
    expect(c.read(aiDailyCommentProvider), isA<AiDailyIdle>());
  });

  test('成功：Ready + 写当日缓存；当天二次调用走缓存；force 跳过缓存',
      () async {
    final c = container();
    await c.read(aiSettingsProvider.notifier).enableWithConsent();
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');

    await c.read(aiDailyCommentProvider.notifier).requestDailyComment();
    expect(fakeLlm.calls, 1);
    final s1 = c.read(aiDailyCommentProvider);
    expect(s1, isA<AiDailyReady>());
    expect((s1 as AiDailyReady).text, '今天节奏不错，下午状态最好。');
    expect(s1.fromCache, isFalse);
    // 上传快照已记录
    expect(prefs.getString('ai_last_upload_json'), contains('daily_comment'));

    await c.read(aiDailyCommentProvider.notifier).requestDailyComment();
    expect(fakeLlm.calls, 1); // 当日缓存命中
    expect((c.read(aiDailyCommentProvider) as AiDailyReady).fromCache, isTrue);

    await c
        .read(aiDailyCommentProvider.notifier)
        .requestDailyComment(force: true);
    expect(fakeLlm.calls, 2); // 换一句：强制走云端
  });

  test('记忆日志（#54）：facts 白名单与规范同步（docs/09 §4.2）', () {
    final facts = dailyFactsJson(fakeSummary);
    // 写出来的键不许超出规范表（防「悄悄多传一个字段」）
    expect(kMemoryFactKeys.containsAll(facts.keys), isTrue,
        reason: 'dailyFactsJson 写出了白名单之外的键：'
            '${facts.keys.where((k) => !kMemoryFactKeys.contains(k))}');
    // 白名单里的键必须能真的渲染出来（不允许「有声明的键但注入时看不见」）
    final block = AiMemoryLog.renderBlock(
        [AiMemoryEntry(date: '2026-09-20', facts: facts)])!;
    expect(block, contains('专注 95 分钟'));
    expect(block, contains('3 段'));
    expect(block, contains('下午为主'));
    // 规范承诺「无钟点」
    expect(RegExp(r'\d{1,2}:\d{2}').hasMatch(jsonEncode(facts)), isFalse);
  });

  test('记忆日志（#54）：点评成功把这一句写进当天条目', () async {
    final c = container();
    await c.read(aiSettingsProvider.notifier).enableWithConsent();
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiDailyCommentProvider.notifier).requestDailyComment();

    final file = await c.read(aiMemoryLogStoreProvider).read();
    final e = file.entries.single;
    expect(e.date, memoryDateKey(DateTime.now()));
    expect(e.note, '今天节奏不错，下午状态最好。');
    expect(e.facts!['focus_minutes'], 95); // 数字与事实块同一来源
  });

  test('记忆日志（#54）：点评失败不写日志（没答案就没有记录）', () async {
    fakeLlm =
        FakeLlm(failure: const LlmFailure(LlmFailureKind.network, 'x'));
    final c = container();
    await c.read(aiSettingsProvider.notifier).enableWithConsent();
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiDailyCommentProvider.notifier).requestDailyComment();
    final file = await c.read(aiMemoryLogStoreProvider).read();
    expect(file.entries, isEmpty);
  });

  test('LLM 失败：静默回 Idle，不抛穿不降级提示', () async {
    fakeLlm =
        FakeLlm(failure: const LlmFailure(LlmFailureKind.network, 'x'));
    final c = container();
    await c.read(aiSettingsProvider.notifier).enableWithConsent();
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiDailyCommentProvider.notifier).requestDailyComment();
    expect(fakeLlm.calls, 1);
    expect(c.read(aiDailyCommentProvider), isA<AiDailyIdle>());
  });

  test('dateKeyOf：本地零点格式化 yyyy-MM-dd', () {
    expect(AiDailyCommentController.dateKeyOf(DateTime(2026, 9, 12, 23, 59)),
        '2026-09-12');
  });

  test('缓存带数据指纹：当天数据未变不提示，变了标 dataUpdated（08-A2）',
      () async {
    final c = container();
    await c.read(aiSettingsProvider.notifier).enableWithConsent();
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiDailyCommentProvider.notifier).requestDailyComment();
    expect(fakeLlm.calls, 1);

    // 数据未变：命中缓存且不提示
    await c.read(aiDailyCommentProvider.notifier).requestDailyComment();
    final same = c.read(aiDailyCommentProvider) as AiDailyReady;
    expect(same.fromCache, isTrue);
    expect(same.dataUpdated, isFalse);
    expect(fakeLlm.calls, 1);

    // 当天又专注了：回看缓存但标过时，且不自动重发（安静原则）
    servedSummary = const DailySummary(
      focusMillis: 140 * 60000,
      rounds: 6,
      sessionCount: 5,
      interruptionCount: 2,
      interruptionMillis: 300000,
      bestSlot: DaySlot.afternoon,
      firstStartMillis: null,
      lastEndMillis: null,
      longestSegmentMillis: 55 * 60000,
    );
    // 生产环境由 focus_controller._invalidateStats() 失效（本轮补入清单）
    c.invalidate(dailySummaryProvider);
    await c.read(aiDailyCommentProvider.notifier).requestDailyComment();
    final stale = c.read(aiDailyCommentProvider) as AiDailyReady;
    expect(stale.fromCache, isTrue);
    expect(stale.dataUpdated, isTrue);
    expect(fakeLlm.calls, 1);
  });

  test('当日点评请求下发 system 与 120 tokens 预算（08-A4/A5）', () async {
    final c = container();
    await c.read(aiSettingsProvider.notifier).enableWithConsent();
    await c.read(aiApiKeyProvider.notifier).setKey('sk-test');
    await c.read(aiDailyCommentProvider.notifier).requestDailyComment();
    expect(fakeLlm.lastPrompt!.maxTokens, kDailyMaxTokens);
    expect(fakeLlm.lastPrompt!.system, contains('原样引用'));
  });
}
