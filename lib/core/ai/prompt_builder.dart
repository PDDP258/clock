/// PromptBuilder（V0.5，纯 Dart 可测）：结构化洞察 → prompt → 响应解析。
///
/// 契约（07 §4，08-A1/A3/A4/A5 加固）：
/// - 数字由本地 InsightEngine 算好，硬约束声明「数字必须原样引用输入」，
///   LLM 不得自行计算或编造；
/// - 事实块来自 [weeklyFactsBlock] 单一来源（与周报问答共用，08-B2）；
/// - 可选 [memory] 注入块由 [composeUserMessage] 放在事实块与任务之间
///   （看板 #54：跨程序记忆日志），System 侧由硬约束第 10 条配套约束；
/// - 角色与硬约束进 system message，数据与任务进 user message（08-A5）；
/// - 输出契约 = ≤3 段自然语言复盘 + 恰好 1 条以「建议：」起头的建议；
/// - 解析走 [splitBlocks] 加固层：单换行分段、Markdown 装饰、前置寒暄
///   都不再导致整体降级；无法解析返回 null（调用方整体降级，
///   永不展示半截乱文）。
library;

import '../insight/insight.dart';
import 'ai_prompt.dart';
import 'response_parse.dart';

/// 云端 LLM 返回的解读（已按契约截断/校验）。
class AiInterpretation {
  const AiInterpretation({required this.paragraphs, required this.suggestion});

  /// 复盘段落（1~3 段）
  final List<String> paragraphs;

  /// 恰好一条可执行建议（已剥「建议：」前缀）
  final String suggestion;
}

/// 由结构化洞察拼装周报解读 prompt。只引用 [WeeklyInsight] 的白名单字段。
///
/// [memory] = 近 7 日记忆注入块（就近 [kMemoryWindowDays] 天，不含当日）；
/// null 时消息与未引入记忆功能时完全一致——记忆是增强，不是必需。
AiPrompt buildPrompt(WeeklyInsight i, {String? memory}) => AiPrompt(
      composeUserMessage(
        intro: '以下是我本周的专注统计：',
        facts: weeklyFactsBlock(i),
        task: '请输出：不超过 3 段自然语言复盘（每段一两句话），'
            '然后另起一段，以「建议：」开头给出恰好一条下周可执行的具体建议。',
        memory: memory,
      ),
      system: systemPrompt('解读我这一周的专注数据，帮助我做出下周的调整。'),
      maxTokens: kWeeklyMaxTokens,
    );

/// 解析 LLM 响应为契约结构。复盘段超过 3 段截断；
/// 找不到「建议」段或复盘为空 → 返回 null（整体降级）。
AiInterpretation? parseInsightResponse(String raw) {
  final blocks = splitBlocks(raw);
  if (blocks.isEmpty) return null;

  var suggestionIdx = -1;
  var suggestion = '';
  for (var i = 0; i < blocks.length; i++) {
    if (!isSuggestionStart(blocks[i])) continue;
    suggestionIdx = i;
    suggestion = suggestionBody(blocks[i]);
    break;
  }
  if (suggestionIdx < 0 || suggestion.isEmpty) return null;

  final paragraphs = <String>[
    for (var i = 0; i < blocks.length; i++)
      if (i != suggestionIdx) blocks[i],
  ];
  if (paragraphs.isEmpty) return null;
  return AiInterpretation(
    paragraphs: paragraphs.length > 3 ? paragraphs.sublist(0, 3) : paragraphs,
    suggestion: suggestion,
  );
}
