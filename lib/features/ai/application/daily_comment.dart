/// AI 当日点评（看板 #46）：一句话级别的每日小结润色。
///
/// 与周报解读（ai_controller.dart）同纪律，但更轻：
/// - 按日缓存（SP `ai_daily_cache` = {date, text, fp}），当天重复查看零请求；
///   缓存带数据指纹，当天数据变化后在卡上给一行被动提示（08-A2）；
/// - 及时触发：完成专注后由 app 壳调 [AiDailyCommentController.autoDailyIfDue]，
///   前置不满足全静默短路（安静原则对主动路径同样成立）；
/// - 失败静默（当日点评是锦上添花，不降级提示、不占 UI）；
/// - 提示词复用 [dailyFactsBlock] 单一事实块（08-B2），
///   token 预算按 40 字契约收到 [kDailyMaxTokens]（08-A4）；
/// - 记忆日志（看板 #54）：请求带近 7 日记忆注入块，成功后再把这一句
///   写回今天的条目（`note` 字段）——外部程序读日志即可看到本机 AI 的看法。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_prompt.dart';
import '../../../core/ai/deepseek_provider.dart';
import '../../../core/ai/llm_provider.dart';
import '../../../core/ai/memory_log.dart';
import '../../../core/ai/response_parse.dart';
import '../../../platform/prefs/prefs_provider.dart';
import '../../stats/application/stats_controller.dart';
import '../../stats/domain/daily_summary.dart';
import 'ai_controller.dart';
import 'ai_memory.dart';

// ---------------------------------------------------------------- 提示词

/// 构造当日点评提示词（白名单数字原样给出，防编造契约同周报）。
///
/// 「一句话」的难点不是凑够 40 字，而是**挑出这一天最值得说的那一点**——
/// 所以把「取舍」这个要求直接写进任务描述，而不是只说「语气平和」
/// （2026-09-26，看板 #53：原「语气平和克制」被模型执行成了气氛平淡的
/// 数据转述）。
///
/// [memory] = 近 7 日记忆注入块（看板 #54）；当日数字已在事实块里，
/// 故注入窗口不含当日。
AiPrompt buildDailyPrompt(DailySummary s, {String? memory}) => AiPrompt(
      composeUserMessage(
        intro: '以下是我某一天的专注统计：',
        facts: dailyFactsBlock(s),
        task: '请用一句话（不超过 40 字）说出这一天最值得我知道的那一点，'
            '要落在数字里的某个关系或反差上，不要泛泛评价，也不要复述总数。',
        memory: memory,
      ),
      system: systemPrompt('用一句话说出我某一天专注数据里最值得注意的一点。'),
      maxTokens: kDailyMaxTokens,
    );

/// 解析点评回复：取首个有意义的行（跳过空行与模型寒暄），
/// 去「点评：」类前缀，超长截断。空文本返回 null（调用方静默处理）。
String? parseDailyComment(String text) {
  final content = firstMeaningfulLine(
      text, const ['点评：', '点评:', '建议：', '建议:']);
  if (content == null) return null;
  // 模型不守 40 字约束时的硬截断（中文按字符近似）
  return content.length > 80 ? '${content.substring(0, 80)}…' : content;
}

// ---------------------------------------------------------------- 状态机

/// 当日点评状态。
sealed class AiDailyState {
  const AiDailyState();
}

/// 未生成（含一切静默短路/失败——当日点评不打扰）
class AiDailyIdle extends AiDailyState {
  const AiDailyIdle();
}

/// 请求中
class AiDailyLoading extends AiDailyState {
  const AiDailyLoading();
}

/// 成功（[fromCache]=true 表示当日缓存命中，未发请求；
/// [dataUpdated]=true 表示命中缓存后今天的专注数据又变了，内容已过时）
class AiDailyReady extends AiDailyState {
  const AiDailyReady(this.text,
      {required this.fromCache, this.dataUpdated = false});

  /// 一句话点评
  final String text;

  /// 是否来自本地缓存
  final bool fromCache;

  /// 缓存内容是否已落后于当前数据（只提示，不自动重发——安静原则）
  final bool dataUpdated;
}

/// 当日点评控制器。
final aiDailyCommentProvider =
    StateNotifierProvider<AiDailyCommentController, AiDailyState>(
        (ref) => AiDailyCommentController(ref));

class AiDailyCommentController extends StateNotifier<AiDailyState> {
  AiDailyCommentController(this._ref) : super(const AiDailyIdle());

  final Ref _ref;

  static const _kCache = 'ai_daily_cache';

  /// 当日缓存键（本地零点 yyyy-MM-dd；与记忆日志的 date 同源）。
  static String dateKeyOf(DateTime day) => memoryDateKey(day);

  /// 用户点击「换一句」/首次生成。[force]=true 跳过当日缓存。
  Future<void> requestDailyComment({bool force = false}) async {
    final settings = _ref.read(aiSettingsProvider);
    if (!settings.enabled || !settings.hasConsent) return; // 未开启：静默
    final apiKey = _ref.read(aiApiKeyProvider);
    if (apiKey.isEmpty) return;

    final prefs = _ref.read(sharedPreferencesProvider);
    final todayKey = dateKeyOf(DateTime.now());
    final now = DateTime.now();
    final summary =
        await _ref.read(dailySummaryProvider(DateTime(now.year, now.month, now.day)).future);
    // 指纹 = 数据指纹 + 提示词版本（ai_prompt.dart）：口径变更同样提示刷新
    final fingerprint = cacheFingerprintOf(summary.dataFingerprint);

    if (!force) {
      final cached = prefs.getString(_kCache);
      if (cached != null) {
        try {
          final map = (jsonDecode(cached) as Map).cast<String, dynamic>();
          final text = map['text'];
          if (map['date'] == todayKey && text is String && text.isNotEmpty) {
            // 指纹不同 = 今天又专注了，缓存内容已过时：只给被动提示（08-A2）
            state = AiDailyReady(text,
                fromCache: true, dataUpdated: map['fp'] != fingerprint);
            return;
          }
        } on FormatException {/* 缓存损坏视为未命中 */}
      }
    }

    state = const AiDailyLoading();
    try {
      // 近 7 日记忆注入块（看板 #54）；无内容/读失败 = null
      final memory =
          await _ref.read(aiMemoryLogServiceProvider).readInjectionBlock();
      // 上传快照（US-AI-A04 同纪律：实际上传字段可核对）。
      // 数字单一来源 [dailyFactsJson]（与事实块、记忆日志同一份口径）
      await prefs.setString(
          'ai_last_upload_json',
          jsonEncode(<String, Object?>{
            'type': 'daily_comment',
            'date': todayKey,
            ...dailyFactsJson(summary),
            if (memory != null) 'memory_block': memory,
          }));

      final vendor = LlmVendor.byId(_ref.read(aiVendorProvider));
      final llm = _ref.read(llmProviderFactoryProvider)(vendor, apiKey);
      final text =
          await llm.generateInsight(buildDailyPrompt(summary, memory: memory));
      final parsed = text == null ? null : parseDailyComment(text);
      if (parsed == null) {
        state = const AiDailyIdle(); // 静默：当日点评失败不降级提示
        return;
      }
      await prefs.setString(
          _kCache,
          jsonEncode(<String, String>{
            'date': todayKey,
            'text': parsed,
            'fp': fingerprint,
          }));
      state = AiDailyReady(parsed, fromCache: false);
      // 记忆日志（看板 #54）：把今天这一句落到今天的条目上
      await _ref.read(aiMemoryLogServiceProvider).saveToday(note: parsed);
    } on LlmFailure {
      state = const AiDailyIdle(); // 静默
    }
  }

  /// 任务完成时的及时触发（用户反馈「AI 要及时触发」）：
  /// 前置不满足（关/未同意/无 Key/请求中/今日已有点评）全静默短路。
  Future<void> autoDailyIfDue() async {
    if (state is AiDailyLoading) return;
    await requestDailyComment(); // 内部含全部短路；今日无缓存才真请求
  }
}
