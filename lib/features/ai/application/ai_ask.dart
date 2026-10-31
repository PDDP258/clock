/// AI 预设问答（看板 #50/#51）：M500 打字困难，点选式「问 AI 一句」。
///
/// 双场景：
/// - 周报问答（统计页）：数据 = WeeklyInsight 白名单，缓存键 `w:周键:题id`；
/// - 当日问答（详细页，可问任意查看日）：数据 = DailySummary 白名单，
///   缓存键 `d:yyyy-MM-dd:题id`。
///
/// 纪律同周报解读/当日点评（ADR-0006 安静原则）：
/// - 仅手动触发（点 chip 才问），不做任何自动提问；
/// - 前置不满足（总开关关/未同意/无 Key）全静默短路，零请求；
/// - 同周/同日同题命中缓存零请求；「换一句」force 跳缓存；
/// - 失败静默回 Idle，不降级提示、不占 UI；
/// - 事实块与解读/点评共用同一来源（08-B2），token 预算 200（08-A4）；
/// - 记忆日志（看板 #54）：问当下（本周 / 今天）才注入近 7 日记忆，
///   问历史某天不注入——那天的数字就是事实块本身，混进记忆只会认错参数。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ai/ai_prompt.dart';
import '../../../core/ai/deepseek_provider.dart';
import '../../../core/ai/llm_provider.dart';
import '../../../core/ai/memory_log.dart';
import '../../../core/ai/response_parse.dart';
import '../../../core/insight/insight.dart';
import '../../../core/insight/insight_engine.dart';
import '../../../platform/prefs/prefs_provider.dart';
import '../../stats/application/stats_controller.dart';
import '../../stats/domain/daily_summary.dart';
import 'ai_controller.dart';
import 'ai_memory.dart';

// ---------------------------------------------------------------- 预设题目

/// 问答场景（决定数据源与缓存键前缀）。
enum AiAskScope {
  /// 本周（数据：WeeklyInsight）
  week,

  /// 指定日（数据：DailySummary）
  day,
}

/// 一道预设问题。
class AiAskQuestion {
  const AiAskQuestion(this.id, this.label, this.scope);

  /// 缓存键用 id
  final String id;

  /// chip 显示文案
  final String label;

  /// 数据场景
  final AiAskScope scope;
}

/// 周报题目（统计页，全部可用周报白名单数据回答）。
///
/// 2026-09-26 扩充（看板 #53）：新增 `interrupt_when` / `worth_it` 两题，
/// 都由 08-B3 新补的洞察字段才答得出来——**题目能否问出「意外」，
/// 取决于手里有没有可对比的数字**，所以这批题和洞察扩容是同一件事。
const aiAskWeeklyQuestions = <AiAskQuestion>[
  AiAskQuestion('best_slot', '我什么时段最专注？', AiAskScope.week),
  AiAskQuestion('interrupt_when', '什么时候最容易被打断？', AiAskScope.week),
  AiAskQuestion('reduce_interrupt', '怎样减少中断？', AiAskScope.week),
  AiAskQuestion('worth_it', '时间花得值吗？', AiAskScope.week),
  AiAskQuestion('next_week', '下周怎么安排？', AiAskScope.week),
];

/// 当日题目（详细页，对任意查看日可问；文案用「这天」兼容历史日期）。
const aiAskDailyQuestions = <AiAskQuestion>[
  AiAskQuestion('day_rhythm', '这天节奏怎么样？', AiAskScope.day),
  AiAskQuestion('day_longest', '最长一段怎么用好的？', AiAskScope.day),
  // 「最值得说的一点」是**强制取舍**的开放题：模型必须挑一个点讲，
  // 而不是把事实块逐行铺开——对付「枯燥」最直接的一招
  AiAskQuestion('day_highlight', '这天最值得说的是什么？', AiAskScope.day),
  AiAskQuestion('day_tomorrow', '明天怎么安排？', AiAskScope.day),
];

// ---------------------------------------------------------------- 提示词

/// 周报问答提示词：白名单数字 + 问题，要求 ≤80 字直接回答。
/// 事实块复用 [weeklyFactsBlock]（与周报解读同源，08-B2）；
/// token 预算收到 [kAskMaxTokens]（80 字契约不需要 600，08-A4）；
/// [memory] = 近 7 日记忆注入块（看板 #54）。
AiPrompt buildAskPrompt(WeeklyInsight i, AiAskQuestion q,
        {String? memory}) =>
    AiPrompt(
      composeUserMessage(
        intro: '以下是我本周的专注统计：',
        facts: weeklyFactsBlock(i),
        task: '我的问题：${q.label}\n请直接回答这个问题，不超过 80 字。',
        memory: memory,
      ),
      system: systemPrompt('回答我关于本周专注数据的一个问题。'),
      maxTokens: kAskMaxTokens,
    );

/// 当日问答提示词：DailySummary 白名单数字 + 问题（事实块与当日点评同源）。
///
/// 只有「问今天」才注入记忆：问历史某天时，那天的数字就是事实块本身，
/// 再塞近 7 日记忆只会让模型把参数搞混。
AiPrompt buildDailyAskPrompt(DailySummary s, AiAskQuestion q,
        {String? memory}) =>
    AiPrompt(
      composeUserMessage(
        intro: '以下是我某一天的专注统计：',
        facts: dailyFactsBlock(s),
        task: '我的问题：${q.label}\n请直接回答这个问题，不超过 80 字。',
        memory: memory,
      ),
      system: systemPrompt('回答我关于某一天专注数据的一个问题。'),
      maxTokens: kAskMaxTokens,
    );

/// 解析问答回复：取首个有意义的行（跳过空行、模型寒暄与 Markdown 装饰），
/// 去「答：」类前缀，超长截断。空文本返回 null（调用方静默处理）。
String? parseAskAnswer(String text) {
  final content = firstMeaningfulLine(
      text, const ['答：', '答:', '回答：', '回答:', '建议：', '建议:']);
  if (content == null) return null;
  return content.length > 120 ? '${content.substring(0, 120)}…' : content;
}

// ---------------------------------------------------------------- 状态机

/// 问答状态（单槽：只记住最近一次提问）。
class AiAskState {
  const AiAskState({this.qid, this.text, this.loading = false});

  /// 当前/最近提问的题目 id；Idle 为 null
  final String? qid;

  /// 回答文本；未回答为 null
  final String? text;

  /// 请求中
  final bool loading;
}

/// 问答控制器。
final aiAskProvider = StateNotifierProvider<AiAskController, AiAskState>(
    (ref) => AiAskController(ref));

class AiAskController extends StateNotifier<AiAskState> {
  AiAskController(this._ref) : super(const AiAskState());

  final Ref _ref;

  static const _kCache = 'ai_ask_cache';

  /// 缓存条目上限（插入序淘汰最旧），防无限膨胀
  static const _kMaxEntries = 30;

  /// 本地零点日期键（yyyy-MM-dd；与记忆日志的 date 同源）。
  static String dateKeyOf(DateTime day) => memoryDateKey(day);

  /// 用户点选某题。[day] 仅当日场景必传（=详细页当前查看日）。
  /// 前置不满足静默 return；命中缓存零请求；[force]=true 跳过缓存（换一句）。
  Future<void> ask(AiAskQuestion question,
      {DateTime? day, bool force = false}) async {
    final settings = _ref.read(aiSettingsProvider);
    if (!settings.enabled || !settings.hasConsent) return; // 静默
    final apiKey = _ref.read(aiApiKeyProvider);
    if (apiKey.isEmpty) return;

    final scopeKey = switch (question.scope) {
      AiAskScope.week => 'w:${isoWeekKey(DateTime.now())}',
      AiAskScope.day => 'd:${dateKeyOf(day ?? DateTime.now())}',
    };
    final cacheKey = '$scopeKey:${question.id}';

    final prefs = _ref.read(sharedPreferencesProvider);
    if (!force) {
      final cached = _readCache(prefs, cacheKey);
      if (cached != null) {
        state = AiAskState(qid: question.id, text: cached);
        return;
      }
    }

    state = AiAskState(qid: question.id, loading: true);
    try {
      final askedDay = day ?? DateTime.now();
      // 记忆注入（看板 #54）：只有「问当下」才给近 7 日记忆。
      // 问历史某天时，那天的数字就是事实块本身，再塞记忆只会让模型认错参数。
      final memory = dateKeyOf(askedDay) == dateKeyOf(DateTime.now())
          ? await _ref.read(aiMemoryLogServiceProvider).readInjectionBlock()
          : null;

      // 数据源与提示词按场景分流；上传快照 type 区分（US-AI-A04 同纪律）
      final AiPrompt prompt;
      final Map<String, Object?> upload;
      switch (question.scope) {
        case AiAskScope.week:
          final insight = await _ref.read(weeklyInsightProvider.future);
          prompt = buildAskPrompt(insight, question, memory: memory);
          upload = <String, Object?>{
            'type': 'ask_week',
            'question': question.label,
            ...insight.toUploadJson(),
          };
        case AiAskScope.day:
          final summary =
              await _ref.read(dailySummaryProvider(askedDay).future);
          prompt = buildDailyAskPrompt(summary, question, memory: memory);
          upload = <String, Object?>{
            'type': 'ask_day',
            'question': question.label,
            'date': dateKeyOf(askedDay),
            // 数字单一来源 [dailyFactsJson]（与事实块、记忆日志同一份口径）
            ...dailyFactsJson(summary),
          };
      }
      // 记忆块也是发出去的内容，如实入快照
      if (memory != null) upload['memory_block'] = memory;
      await prefs.setString('ai_last_upload_json', jsonEncode(upload));

      final vendor = LlmVendor.byId(_ref.read(aiVendorProvider));
      final llm = _ref.read(llmProviderFactoryProvider)(vendor, apiKey);
      final text = await llm.generateInsight(prompt);
      final parsed = text == null ? null : parseAskAnswer(text);
      if (parsed == null) {
        state = const AiAskState(); // 静默
        return;
      }
      await _writeCache(prefs, cacheKey, parsed);
      state = AiAskState(qid: question.id, text: parsed);
    } on LlmFailure {
      state = const AiAskState(); // 静默
    }
  }

  String? _readCache(SharedPreferences prefs, String cacheKey) {
    final raw = prefs.getString(_kCache);
    if (raw == null) return null;
    try {
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final text = map[cacheKey];
      return text is String && text.isNotEmpty ? text : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeCache(
      SharedPreferences prefs, String cacheKey, String text) async {
    // LinkedHashMap 保插入序：超上限时淘汰最旧条目
    Map<String, dynamic> map = {};
    final raw = prefs.getString(_kCache);
    if (raw != null) {
      try {
        map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      } on FormatException {/* 损坏则重建 */}
    }
    map.remove(cacheKey); // 重写到末尾，刷新新旧
    map[cacheKey] = text;
    while (map.length > _kMaxEntries) {
      map.remove(map.keys.first);
    }
    await prefs.setString(_kCache, jsonEncode(map));
  }
}
