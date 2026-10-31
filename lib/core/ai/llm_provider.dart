/// 云端 LLM 服务商抽象（V0.5，core 层纯 Dart，业务只依赖本接口）。
///
/// 契约（07 §3）：只做自然语言润色；任何失败都必须可降级，
/// 不得抛穿业务层为非 [LlmFailure] 异常。
library;

import 'ai_prompt.dart';

/// 云端 LLM 服务商抽象：首选 DeepSeek，可换 Kimi / 通义千问。
abstract class LlmProvider {
  /// 服务商标识（deepseek / kimi / qwen）
  String get id;

  /// 由 [AiPrompt] 生成解读文案（system/user 分消息 + 本次 token 预算）。
  /// 返回 null 表示不可用（未配置 Key，未发请求）；失败统一抛
  /// [LlmFailure]，调用方一律捕获并降级为结构化周报。
  Future<String?> generateInsight(AiPrompt prompt);

  /// 连通性自测（设置页「测试 Key」用）：成功返回 true。
  Future<bool> ping();
}

/// 失败分类（07 §3）：除 unauthorized/quota 在 UI 给一行提示外，
/// 其余静默降级为结构化周报。
enum LlmFailureKind { network, timeout, unauthorized, quota, badResponse }

/// LLM 调用失败。携带分类与原始摘要（仅 debugPrint 用，不上报）。
class LlmFailure implements Exception {
  const LlmFailure(this.kind, [this.detail]);

  /// 失败分类
  final LlmFailureKind kind;

  /// 原始摘要（HTTP 状态码或异常短描述）
  final String? detail;

  @override
  String toString() => 'LlmFailure($kind${detail == null ? '' : ', $detail'})';
}
