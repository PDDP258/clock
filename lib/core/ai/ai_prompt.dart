/// 提示词层（08-AI功能优化建议 §3/§4 落地）。
///
/// 设计要点：
/// - **system 与 user 分离**（08-A5）：角色与硬约束进 system message，
///   数据与本次任务进 user message——主流服务商对 system 的指令遵循度更高；
/// - **事实块单一来源**（08-B2）：周报/当日两组事实块各只有一个实现，
///   四个 builder 共用，补字段不会出现两套口径；
/// - **token 预算按任务分档**（08-A4）：非流式请求的等待时间 ≈ max_tokens ÷
///   生成速率，点评/问答沿用周报的 600 预算是纯白等；
/// - **部分周如实声明**（08-A1）：本周是「周一至今」的进行中数据，
///   必须在 prompt 里说清楚，否则 LLM 会拿半周数据下「退步」结论；
/// - **反鸡汤 ≠ 去性格**（2026-09-26，看板 #53）：曾经的「克制、务实」
///   被模型执行成了逐行复述数字，读起来枯燥。现在把边界重新划在
///   「每句话都要对得回数字」上，而不是「语气必须中性」——见 [_hardRules]。
/// - **近 7 日记忆是一等输入**（2026-09-26，看板 #54）：[composeUserMessage]
///   在事实块与任务之间插入记忆日志的注入块，四个 builder 共用同一位置；
///   记忆块本身由 core/ai/memory_log.dart 渲染（含 900 字硬上限）。
///   提示词是发出去的东西，所以「记忆里有什么」必须与「本机承诺发什么」
///   同一份口径——这也是本轮顺手修掉 `- 起止：HH:mm` 的原因。
library;

import '../../features/stats/domain/daily_summary.dart';
import '../../features/stats/domain/weekly_report.dart' show DaySlotX;
import '../insight/insight.dart';

// ---------------------------------------------------------------- token 预算

/// 周报解读预算（≤3 段复盘 + 1 条建议）
const int kWeeklyMaxTokens = 600;

/// 问答预算（契约 ≤80 字，中文约 1.2~1.5 token/字，留一倍余量）
const int kAskMaxTokens = 200;

/// 当日点评预算（契约 ≤40 字）
const int kDailyMaxTokens = 120;

/// 默认预算（未显式分档时的兜底）
const int kDefaultMaxTokens = kWeeklyMaxTokens;

// ---------------------------------------------------------------- 缓存版本

/// 提示词版本：**改动提示词或事实块口径时必须递增**。
///
/// v2 = 2026-09-26 调性重构 + 08-B3 洞察扩容（看板 #53）。
/// v3 = 2026-09-26 近 7 日记忆注入 + 事实块去掉钟点（看板 #54）：
///      输入增了「记忆」这一节，且当日事实块口径变了（见 [dailyFactsBlock]），
///      旧缓存里的解读是另一套输入下的产物，必须让它显示「数据已更新」。
const String kPromptVersion = 'v3';

/// 缓存比对指纹 = 数据指纹 + 提示词版本。
///
/// 两者缺一不可：只用数据指纹会漏掉「口径变了」——用户改了提示词，
/// 却还在读 v1 文风写出来的旧解读，看起来像没改；只用版本号则会让
/// 每次数据变化都失灵。任一变化都只给一行被动提示，不自动重发
/// （安静原则，照 08-A2）。
String cacheFingerprintOf(String dataFingerprint) =>
    '$dataFingerprint@$kPromptVersion';

// ---------------------------------------------------------------- 提示词载体

/// 一次 AI 请求的提示词。
///
/// [system] 与 [user] 分属两条 message：前者是跨任务稳定的角色与硬约束，
/// 后者是本任务的白名单数据与问题。
class AiPrompt {
  const AiPrompt(this.user, {this.system, this.maxTokens = kDefaultMaxTokens});

  /// 用户消息：白名单数据 + 本次任务
  final String user;

  /// 系统消息：角色与硬约束（null = 不发送 system message）
  final String? system;

  /// 本次请求的 token 预算（直接决定非流式请求的等待时间）
  final int maxTokens;
}

// ---------------------------------------------------------------- system 提示词

/// 跨任务稳定的角色设定。
///
/// 2026-09-26 修订：原设定「克制、务实的复盘助手」被模型过度执行成了
/// 「平铺数字复述」（用户反馈「AI 功能太枯燥」）。改为强调**发现关系、
/// 说人话**——克制的是判断的依据，不是表达的语气。
const String _role = '你是一位专注数据复盘搭档，服务于一台零触屏自律时钟。'
    '你擅长从少量数字里看出别人没注意到的关系，并用平实、有画面感的话讲出来。';

/// 全部任务共用的硬约束。
///
/// 分三组写是有意的，各组对应一个已知失败模式：
/// - **【数字纪律】防编造**——本模块第一红线，错了不如不说（08-A1 的教训：
///   喂错前提时，模型对指令的服从度越高错得越离谱）；
/// - **【禁止空洞】只禁「没有信息量的表达」，不禁语气**——「表现不错」的
///   毛病在于把数字换成了形容词，而不在于它是一句正面的话；
/// - **【要求具体】是解「枯燥」的正解**——08-A5 那版只有「禁」没有「要」，
///   模型于是选了最安全的写法：照事实块逐行复述。逐行复述必然枯燥，
///   因为读者自己也能看到那些数字。
const String _hardRules = '''
硬约束（必须全部遵守）：

【数字纪律】
1. 数字只能原样引用我给出的数据，不得自行计算、换算、取整或编造任何数字。
2. 数据不足以支撑判断时，直接说明「数据还太少，暂不足以判断」，
   不要为了填满篇幅而编造趋势，也不要勉强给建议。

【禁止空洞】
3. 不写没有信息量的评价与鼓励语（如「表现不错」「继续保持」「加油」
   「相信自己」「坚持就是胜利」）——每句话都要能对回具体数字；
   不说教、不评判我的人格。
4. 只谈专注时长、时段分布、中断这类可观测数据；不做健康、心理或人生建议。

【要求具体】
5. 至少给出一处数字之间的关系：本周与上周同期比、时段之间比、最长一段与
   平均一段比、中断集中在哪一段——让我看到「关系」，而不只是「数字」。
6. 数据里有反直觉的地方就直接点出来（最专注时段比想当然的更集中、
   中断集中在某个时段、最长一段出现在非常规时间）。
7. 第一句必须是「发现」，不是「概述」：不要写「本周专注 620 分钟，共 21 次」
   这种我一眼就能看到的复述，要写「你的 620 分钟有近一半挤在晚上」
   这种我看了才知道的关系。
8. 可以说人话、可以用比喻和短句，只要每个判断都对得回上面给出的数字。

【格式】
9. 不使用标题、列表、项目符号、加粗或表情符号。

【记忆引用】
10. 如果我给了「近 7 日记忆」，它是我这几天的历史日志，只用来看延续性与习惯；
    其中的数字属于过去，不要拿它当作本次数据，也不要与本次数据混算或对比。''';

/// 组装 system 消息：角色 + 硬约束 + 本任务说明。
String systemPrompt(String task) => '$_role\n\n$_hardRules\n\n本次任务：$task';

// ---------------------------------------------------------------- 事实块

/// 周报白名单事实块（周报解读与周报问答共用，08-B2）。
///
/// 08-B3 扩充后事实从 8 行涨到 12~13 行——**行数本身就是「不枯燥」的前提**：
/// 只有 8 个孤立数字时，模型只能逐行复述；有了一组能互相比较的数字
/// （时段之间、最长与平均之间、中断与专注之间），它才有东西可以「发现」。
String weeklyFactsBlock(WeeklyInsight i) {
  final buffer = StringBuffer()
    ..writeln('- 本周进度：周一至今共 ${i.daysElapsed} 天（进行中的部分周，'
        '请不要把本周总量当成一整周的量）')
    ..writeln('- 本周专注：${i.thisWeekMinutes} 分钟，共 ${i.sessionCount} 次'
        '（完成 ${i.rounds} 轮）');
  if (i.changeRatio != null) {
    final pct = (i.changeRatio! * 100).toStringAsFixed(1);
    final sign = i.changeRatio! >= 0 ? '+' : '';
    buffer
      ..writeln('- 上周同期：${i.lastWeekMinutes} 分钟')
      ..writeln('- 环比上周同期：$sign$pct%');
  } else {
    // 上周同期无记录：不给数字也不给对比，防止 LLM 自行折算（08-A1）
    buffer.writeln('- 上周同期无专注记录，本次不提供对比，不要据此判断增减趋势');
  }
  if (i.bestDayWeekday != null) {
    buffer.writeln('- 最专注的一天：${weekdayLabel(i.bestDayWeekday!)}'
        ' ${i.bestDayMinutes} 分钟');
  }
  buffer.writeln('- 有专注记录的天数：${i.activeDays} 天');
  if (i.slotDistribution.isNotEmpty) {
    final slots = i.slotDistribution.entries
        .map((e) => '${e.key.label} ${(e.value * 100).round()}%')
        .join('、');
    buffer.writeln('- 时段分布：$slots');
  }
  if (i.bestSlot != null) {
    buffer.writeln('- 最专注时段：${i.bestSlot!.label}');
  }
  if (i.longestSegmentMinutes > 0) {
    final where = i.longestSegmentSlot == null
        ? ''
        : '（出现在${i.longestSegmentSlot!.label}）';
    buffer.writeln('- 最长连续一段：${i.longestSegmentMinutes} 分钟$where');
  }
  // 中断一组行内合并：次数 / 总时长 / 占专注比例 / 单次均值——四个数
  // 放在一行里，模型一眼就能看出「中断到底算不算问题」
  final interruption = StringBuffer('- 中断：${i.interruptionCount} 次');
  if (i.interruptionMinutes > 0) {
    interruption.write('，共 ${i.interruptionMinutes} 分钟');
  }
  if (i.interruptionRatio != null && i.interruptionMinutes > 0) {
    interruption.write('（占专注时长 ${(i.interruptionRatio! * 100).round()}%');
    if (i.avgInterruptionMinutes > 0) {
      interruption.write('，单次平均 ${i.avgInterruptionMinutes} 分钟');
    }
    interruption.write('）');
  }
  buffer.writeln(interruption.toString());
  if (i.interruptionSlotDistribution.isNotEmpty) {
    final slots = i.interruptionSlotDistribution.entries
        .map((e) => '${e.key.label} ${(e.value * 100).round()}%')
        .join('、');
    // 标注「按次数」：未闭合的进行中暂停没有时长，口径要诚实（08-B3）
    buffer.writeln('- 中断时段分布（按次数）：$slots');
  }
  buffer.writeln('- 弹性连续：${i.streakDays} 天（本周缓冲已用 ${i.bufferUsed} 天）');
  return buffer.toString();
}

/// 当日白名单数字（**单一来源**）：事实块文本、上传快照、记忆日志共用一份。
///
/// 只有时长/轮数/时段这类聚合量，**不含钟点**。这一条不是风格问题：
/// 07 §5.1 与设置页的数据使用说明都向用户承诺过「逐次会话起止明细
/// 永远不上传」「不发送具体时间点」，而 2026-09-26 修正前的事实块
/// 确实把 `- 起止：从 09:12 到 18:40` 写进了提示词——
/// 模型看得见的东西就是发出去了的东西（看板 #54）。
Map<String, Object?> dailyFactsJson(DailySummary s) => <String, Object?>{
      'focus_minutes': (s.focusMillis / 60000).round(),
      'sessions': s.sessionCount,
      'rounds': s.rounds,
      'longest_segment_minutes': (s.longestSegmentMillis / 60000).round(),
      'interruption_count': s.interruptionCount,
      'interruption_minutes': (s.interruptionMillis / 60000).round(),
      if (s.bestSlot != null) 'best_slot': s.bestSlot!.label,
    };

/// 当日白名单事实块（当日点评与当日问答共用，08-B2）。
/// 数字全部取自 [dailyFactsJson]，避免「同一份数据两套口径」。
String dailyFactsBlock(DailySummary s) {
  final f = dailyFactsJson(s);
  final minutes = f['focus_minutes'] as int;
  final buffer = StringBuffer()
    ..writeln('- 专注时长：$minutes 分钟')
    ..writeln('- 分 ${f['sessions']} 段完成，完成 ${f['rounds']} 个番茄')
    ..writeln('- 最长一段：${f['longest_segment_minutes']} 分钟');
  final slot = f['best_slot'];
  if (slot != null) buffer.writeln('- 最佳时段：$slot');
  buffer.writeln('- 中断：${f['interruption_count']} 次，'
      '共 ${f['interruption_minutes']} 分钟');
  if (minutes == 0) {
    buffer.writeln('（这一天没有专注记录）');
  }
  return buffer.toString();
}

// ---------------------------------------------------------------- 消息组装

/// 组装 user message：前言 → 本次数据 →（可选）近 7 日记忆 → 本次任务。
///
/// 记忆夹在**数据之后、任务之前**是有意的：任务指令留在末尾
/// （模型对末位指令的遵循度最高），记忆作为背景与之隔开一段，
/// 降低被当成「本次数据」的概率；system 硬约束第 10 条再从另一侧约束一次。
/// [memory] 为 null 时输出与未引入记忆功能时逐字符一致。
String composeUserMessage({
  required String intro,
  required String facts,
  required String task,
  String? memory,
}) =>
    memory == null ? '$intro\n\n$facts\n$task' : '$intro\n\n$facts\n$memory\n\n$task';
