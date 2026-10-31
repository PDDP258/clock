/// AI 控制器（V0.5）：总开关/单独同意/API Key/解读请求与缓存/降级状态。
///
/// 红线（AI 安静原则，ADR-0006）：
/// - 总开关默认关闭；开启必须经 [AiSettingsNotifier.enableWithConsent]
///   （UI 先弹数据使用说明，用户同意后才会走到这里）；
/// - 总开关关闭或无同意时 [AiInsightController.requestInterpretation]
///   直接降级，**零网络请求**；
/// - 一切云端失败静默降级为结构化周报，不抛穿、不弹错误对话框。
///
/// 本轮加固（08-A2/A4/A6）：
/// - 同周缓存带**数据指纹**：本周数据变化后缓存仍可回看，但在卡上给一行
///   被动提示「数据已更新」（不自动重发，安静原则不变）；
/// - **数据量门槛**：本周专注不足门槛时直接降级 `insufficientData`，
///   不发那一次必然只换来鸡汤的请求；
/// - token 预算按任务分档（见 ai_prompt.dart）。
///
/// 跨程序记忆（2026-09-26，看板 #54）：请求前取近 7 日记忆注入块
/// （[AiMemoryLogService.readInjectionBlock]），成功后把本次解读落到
/// 今天的日志条目上。[ai_memory.dart] 与本文件互有 import——
/// 都在 `features/ai/application/` 这一层，Dart 允许循环 import，
/// 为的是让「是否写入」这个闸门只存在于服务内部一处，调用方不必各自记得。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ai/ai_prompt.dart';
import '../../../core/ai/deepseek_provider.dart';
import '../../../core/ai/llm_provider.dart';
import '../../../core/ai/prompt_builder.dart';
import '../../../core/insight/insight.dart';
import '../../../core/insight/insight_engine.dart';
import '../../../platform/db/app_database.dart';
import '../../../platform/prefs/prefs_provider.dart';
import '../../stats/application/stats_controller.dart';
import '../../stats/domain/focus_interruption.dart';
import 'ai_memory.dart';

// ---------------------------------------------------------------- 设置状态

/// AI 设置快照（总开关 + 单独同意记录）。
class AiSettings {
  const AiSettings({
    required this.enabled,
    required this.consentAtMillis,
    required this.consentVersion,
  });

  /// 总开关（默认 false）
  final bool enabled;

  /// 单独同意的墙上时间戳；null = 未同意
  final int? consentAtMillis;

  /// 同意的数据使用说明文案版本
  final String? consentVersion;

  /// 是否已单独同意（开启的前提）
  bool get hasConsent => consentAtMillis != null;
}

/// AI 设置的读写与持久化（shared_preferences）。
class AiSettingsNotifier extends StateNotifier<AiSettings> {
  AiSettingsNotifier(this._prefs)
      : super(AiSettings(
          enabled: _prefs.getBool(_kEnabled) ?? false,
          consentAtMillis: _prefs.getInt(_kConsentAt),
          consentVersion: _prefs.getString(_kConsentVersion),
        ));

  static const _kEnabled = 'ai_enabled';
  static const _kConsentAt = 'ai_consent_at';
  static const _kConsentVersion = 'ai_consent_version';
  static const _kCache = 'ai_insight_cache';
  static const _kLastUpload = 'ai_last_upload_json';

  /// 当前数据使用说明文案版本（文案变更需升版本号重新征得同意）。
  ///
  /// v2 = 2026-09-26 增加「近 7 日记忆日志随请求发送」披露（看板 #54）——
  /// 记忆日志里可能含外部程序写入的内容，属于上传面的实质变化。
  static const currentConsentVersion = 'v2';

  final SharedPreferences _prefs;

  /// 开启总开关并记录单独同意（UI 须在调用前展示数据使用说明）。
  Future<void> enableWithConsent() async {
    final at = DateTime.now().millisecondsSinceEpoch;
    state = AiSettings(
        enabled: true, consentAtMillis: at, consentVersion: currentConsentVersion);
    await _prefs.setBool(_kEnabled, true);
    await _prefs.setInt(_kConsentAt, at);
    await _prefs.setString(_kConsentVersion, currentConsentVersion);
  }

  /// 一键全局关闭（US-AI-D01）：停止一切云端请求、撤销同意记录。
  /// 反悔成本为零——解读缓存与 Key 保留，重开即可用；要清数据用
  /// [deleteAiData]。
  Future<void> disable() async {
    state = AiSettings(
        enabled: false,
        consentAtMillis: null,
        consentVersion: state.consentVersion);
    await _prefs.setBool(_kEnabled, false);
    await _prefs.remove(_kConsentAt);
  }

  /// 删除全部 AI 数据（US-AI-D04）：解读缓存、同意记录、上传快照，
  /// 并关闭总开关。API Key 属用户凭证，一并清除（删除=彻底离开）。
  Future<void> deleteAiData() async {
    await disable();
    await _prefs.remove(_kCache);
    await _prefs.remove(_kLastUpload);
    for (final v in LlmVendor.presets) {
      await _prefs.remove(AiApiKeyNotifier.keyOf(v.id));
    }
  }
}

/// AI 设置（总开关/同意）Provider。
final aiSettingsProvider =
    StateNotifierProvider<AiSettingsNotifier, AiSettings>(
        (ref) => AiSettingsNotifier(ref.watch(sharedPreferencesProvider)));

// ---------------------------------------------------------------- 厂商与 Key

/// 当前 LLM 服务商（默认 DeepSeek），持久化。
final aiVendorProvider = StateNotifierProvider<AiVendorNotifier, String>(
    (ref) => AiVendorNotifier(ref.watch(sharedPreferencesProvider)));

/// 服务商的读写与持久化。
class AiVendorNotifier extends StateNotifier<String> {
  AiVendorNotifier(this._prefs)
      : super(_prefs.getString(_kVendor) ?? LlmVendor.deepseek.id);

  static const _kVendor = 'ai_vendor';
  final SharedPreferences _prefs;

  Future<void> setVendor(String id) async {
    state = LlmVendor.byId(id).id;
    await _prefs.setString(_kVendor, state);
  }
}

/// 当前厂商的 API Key（按厂商分键存储，切换厂商互不覆盖）。
final aiApiKeyProvider = StateNotifierProvider<AiApiKeyNotifier, String>(
    (ref) => AiApiKeyNotifier(
        ref.watch(sharedPreferencesProvider), ref.watch(aiVendorProvider)));

/// Key 的读写与持久化。不日志、不上报、不经任何分析通道（07 §3）。
class AiApiKeyNotifier extends StateNotifier<String> {
  AiApiKeyNotifier(this._prefs, String vendorId)
      : _vendorId = vendorId,
        super(_prefs.getString(keyOf(vendorId)) ?? '');

  final SharedPreferences _prefs;
  final String _vendorId;

  /// 某厂商的 SP 键
  static String keyOf(String vendorId) => 'ai_api_key_$vendorId';

  Future<void> setKey(String key) async {
    state = key.trim();
    if (state.isEmpty) {
      await _prefs.remove(keyOf(_vendorId));
    } else {
      await _prefs.setString(keyOf(_vendorId), state);
    }
  }
}

// ---------------------------------------------------------------- 洞察数据

/// 本周结构化洞察（本地规则引擎产出；无网/未配置 Key 时周报照常工作）。
final weeklyInsightProvider = FutureProvider<WeeklyInsight>((ref) async {
  final dao = ref.watch(appDatabaseProvider).focusSessionDao;
  final streak = await ref.watch(streakProvider.future);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
  final sessions = await dao.sessionsOfRange(
    thisWeekStart.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
    thisWeekStart.add(const Duration(days: 7)).millisecondsSinceEpoch,
  );
  return buildWeeklyInsight(
    sessions: [
      for (final s in sessions)
        InsightSessionFact(
          startAtMillis: s.startAt,
          focusMillis: s.actualFocusMillis,
          rounds: s.rounds,
          pauses: parseInterruptions(s.pausesJson),
        ),
    ],
    streak: streak,
    now: now,
  );
});

// ---------------------------------------------------------------- 解读请求

/// 降级原因（对应 07 §6 降级矩阵；UI 各配一行提示文案）。
/// `insufficientData` 为本轮新增（08-A6）：不是故障，是「本周数据还太少」。
enum AiDegradeReason {
  disabled,
  noConsent,
  noKey,
  insufficientData,
  network,
  timeout,
  unauthorized,
  quota,
  badResponse,
}

/// 解读请求状态机。
sealed class AiInsightState {
  const AiInsightState();
}

/// 未请求
class AiInsightIdle extends AiInsightState {
  const AiInsightIdle();
}

/// 请求中
class AiInsightLoading extends AiInsightState {
  const AiInsightLoading();
}

/// 成功（[fromCache]=true 表示同周缓存命中，未发请求；
/// [dataUpdated]=true 表示命中缓存后本周数据又变了，内容已过时）
class AiInsightReady extends AiInsightState {
  const AiInsightReady(this.value,
      {required this.fromCache, this.dataUpdated = false});

  /// 解读内容（≤3 段复盘 + 1 条建议）
  final AiInterpretation value;

  /// 是否来自本地缓存
  final bool fromCache;

  /// 缓存内容是否已落后于当前数据（只提示，不自动重发——安静原则）
  final bool dataUpdated;
}

/// 已降级（结构化周报照常显示，此处只给一行原因）
class AiInsightDegraded extends AiInsightState {
  const AiInsightDegraded(this.reason);

  /// 降级原因
  final AiDegradeReason reason;
}

/// LLM Provider 工厂（测试接缝：override 换 fake，验证零请求路径）。
final llmProviderFactoryProvider =
    Provider<LlmProvider Function(LlmVendorConfig vendor, String apiKey)>(
  (ref) => (vendor, apiKey) =>
      OpenAiCompatibleLlmProvider(vendor: vendor, apiKey: apiKey),
);

/// 解读请求控制器。
final aiInsightControllerProvider =
    StateNotifierProvider<AiInsightController, AiInsightState>(
        (ref) => AiInsightController(ref));

/// 「AI 解读」的触发与降级矩阵实现（用户主动点击的唯一入口）。
class AiInsightController extends StateNotifier<AiInsightState> {
  AiInsightController(this._ref) : super(const AiInsightIdle());

  final Ref _ref;

  SharedPreferences get _prefs => _ref.read(sharedPreferencesProvider);

  /// 用户点击「AI 解读」。任何前置条件不满足都直接降级且零网络请求；
  /// 同周有缓存直接回看（US-AI-A05）；[force]=true 跳过缓存强制重新解读
  /// （统计页「重新解读」按钮）。
  ///
  /// 顺序说明：先取本地洞察（纯 DB 读，非网络请求），才能算出数据指纹，
  /// 因此洞察在缓存判断之前取——缓存命中与否的决策依赖它。
  Future<void> requestInterpretation({bool force = false}) async {
    final settings = _ref.read(aiSettingsProvider);
    if (!settings.enabled) {
      state = const AiInsightDegraded(AiDegradeReason.disabled);
      return;
    }
    if (!settings.hasConsent) {
      state = const AiInsightDegraded(AiDegradeReason.noConsent);
      return;
    }

    final insight = await _ref.read(weeklyInsightProvider.future);

    // 同周缓存命中：直接回看，不请求云端；
    // 指纹不同 = 本周数据已变化，只给一行被动提示（08-A2）
    final weekKey = isoWeekKey(DateTime.now());
    if (!force) {
      final cached = _prefs.getString(AiSettingsNotifier._kCache);
      if (cached != null) {
        try {
          final map = (jsonDecode(cached) as Map).cast<String, dynamic>();
          if (map['week'] == weekKey) {
            final parsed = parseInsightResponse(map['text'] as String? ?? '');
            if (parsed != null) {
              state = AiInsightReady(
                parsed,
                fromCache: true,
                // 指纹 = 数据指纹 + 提示词版本（ai_prompt.dart）：
                // 数据没变但解读口径变了时同样提示刷新，否则用户会以为
                // 「改了提示词却没生效」
                dataUpdated:
                    map['fp'] != cacheFingerprintOf(insight.dataFingerprint),
              );
              return;
            }
          }
        } on FormatException {
          // 缓存损坏视为未命中，继续走请求路径
        }
      }
    }

    final apiKey = _ref.read(aiApiKeyProvider);
    if (apiKey.isEmpty) {
      state = const AiInsightDegraded(AiDegradeReason.noKey);
      return;
    }

    // 数据量门槛（08-A6）：本周只有 25 分钟时解读必然是一段鸡汤，
    // 既浪费一次调用又拉低输出质量——直接在本地拦下
    if (!insight.isSufficient) {
      state = const AiInsightDegraded(AiDegradeReason.insufficientData);
      return;
    }

    state = const AiInsightLoading();
    // 近 7 日记忆注入块（看板 #54）：无内容/读失败 = null，
    // 此时提示词与未引入记忆功能时逐字符一致
    final memory =
        await _ref.read(aiMemoryLogServiceProvider).readInjectionBlock();
    // US-AI-A04：记录本次实际上传字段（发送前快照，逐字段可核对）；
    // 记忆块也是发出去的内容，同样如实入快照
    await _prefs.setString(
        AiSettingsNotifier._kLastUpload,
        jsonEncode(<String, Object?>{
          ...insight.toUploadJson(),
          if (memory != null) 'memory_block': memory,
        }));

    final vendor = LlmVendor.byId(_ref.read(aiVendorProvider));
    final llm = _ref.read(llmProviderFactoryProvider)(vendor, apiKey);
    try {
      final text = await llm.generateInsight(buildPrompt(insight, memory: memory));
      if (text == null) {
        state = const AiInsightDegraded(AiDegradeReason.noKey);
        return;
      }
      final parsed = parseInsightResponse(text);
      if (parsed == null) {
        state = const AiInsightDegraded(AiDegradeReason.badResponse);
        return;
      }
      await _prefs.setString(
          AiSettingsNotifier._kCache,
          jsonEncode(<String, String>{
            'week': weekKey,
            'text': text,
            'fp': cacheFingerprintOf(insight.dataFingerprint),
          }));
      state = AiInsightReady(parsed, fromCache: false);
      // 记忆日志（看板 #54）：把这次解读落到「今天」这一条上。
      // 存压平后的单行形态而不是原始回复：日志要能被人 diff，
      // 也要能被外部脚本按行读；换行在 JSON 里会变成 \n 转义，不适合阅读。
      await _ref.read(aiMemoryLogServiceProvider).saveToday(
            insight: '${parsed.paragraphs.join(' ')} 建议：${parsed.suggestion}',
          );
    } on LlmFailure catch (e) {
      state = AiInsightDegraded(switch (e.kind) {
        LlmFailureKind.network => AiDegradeReason.network,
        LlmFailureKind.timeout => AiDegradeReason.timeout,
        LlmFailureKind.unauthorized => AiDegradeReason.unauthorized,
        LlmFailureKind.quota => AiDegradeReason.quota,
        LlmFailureKind.badResponse => AiDegradeReason.badResponse,
      });
    }
  }

  /// 任务完成时的主动触发（2026-09-10 用户反馈「推荐任务完成时触发」）：
  /// 每完成一轮专注由 app 壳调用一次；本周首次完成才真正发请求，
  /// 之后靠同周缓存静默短路。前置条件不满足（关/未同意/无 Key/请求中/
  /// 本周已解读/本周数据还太少）全部**静默返回**——不置降级态、不打扰、
  /// 零请求，安静原则对主动路径同样成立（用户开启 + 同意 + 配 Key
  /// 即授权此行为）。
  Future<void> autoInterpretIfDue() async {
    final settings = _ref.read(aiSettingsProvider);
    if (!settings.enabled || !settings.hasConsent) return;
    if (_ref.read(aiApiKeyProvider).isEmpty) return;
    if (state is AiInsightLoading) return;

    final weekKey = isoWeekKey(DateTime.now());
    final cached = _prefs.getString(AiSettingsNotifier._kCache);
    if (cached != null) {
      try {
        final map = (jsonDecode(cached) as Map).cast<String, dynamic>();
        if (map['week'] == weekKey) return; // 本周已有解读，静默短路
      } on FormatException {
        // 缓存损坏视为无缓存，继续
      }
    }

    // 数据还太少时不自动发请求（08-A6）：首轮完成时本周只有一轮的量，
    // 那个时点的解读价值最低——静默等待，凑够门槛后的下一次完成再触发
    final insight = await _ref.read(weeklyInsightProvider.future);
    if (!insight.isSufficient) return;

    await requestInterpretation();
  }
}

/// 最近一次实际上传字段的快照（设置页「查看实际上传字段」用）。
final aiLastUploadJsonProvider = Provider<String?>(
    (ref) => ref.watch(sharedPreferencesProvider).getString('ai_last_upload_json'));
