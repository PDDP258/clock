/// PromptBuilder 单测（V0.5：洞察 JSON → prompt → 响应解析契约）。
///
/// 语义要点：
/// - prompt 包含且仅包含白名单字段的值，数字原样出现在文本中；
/// - changeRatio 为 null（上周同期无基线）时不给数字也不给对比；
/// - 硬约束落在 system 消息（08-A5），且**分「禁空洞」与「要具体」两组**
///   （2026-09-26 调性重构，看板 #53）；
/// - 部分周如实声明 + 600 tokens 预算（08-A1/A4）；
/// - 08-B3 新洞察字段（中断时段分布/占比/最长段/最佳日/有记录天数）全部进事实块；
/// - 响应解析：≤3 段复盘 + 恰好 1 条「建议：」；超长截断、乱文降级 null；
///   单换行分段 / Markdown 加粗 / 前置寒暄都不再导致降级（08-A3）。
library;

import 'package:ai_clock/core/ai/ai_prompt.dart';
import 'package:ai_clock/core/ai/memory_log.dart';
import 'package:ai_clock/core/ai/prompt_builder.dart';
import 'package:ai_clock/core/insight/insight.dart';
import 'package:ai_clock/features/stats/domain/weekly_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WeeklyInsight insight({double? ratio = 0.148}) => WeeklyInsight(
        thisWeekMinutes: 620,
        lastWeekMinutes: 540,
        changeRatio: ratio,
        sessionCount: 21,
        rounds: 17,
        slotDistribution: const {
          DaySlot.morning: 0.45,
          DaySlot.afternoon: 0.3,
          DaySlot.evening: 0.25,
        },
        bestSlot: DaySlot.morning,
        streakDays: 5,
        bufferUsed: 1,
        interruptionCount: 6,
        interruptionMinutes: 32,
        interruptionSlotDistribution: const {
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

  group('buildPrompt', () {
    test('包含全部白名单数字（原样出现）', () {
      final p = buildPrompt(insight());
      for (final token in ['620', '540', '21', '17', '5', '6', '32']) {
        expect(p.user, contains(token), reason: '缺少 $token');
      }
      expect(p.user, contains('上午'));
      expect(p.user, contains('45%'));
    });

    test('环比为正带 + 号与百分比', () {
      expect(buildPrompt(insight()).user, contains('+14.8%'));
    });

    test('上周同期无基线：不给数字也不给对比表述', () {
      final p = buildPrompt(insight(ratio: null));
      expect(p.user, isNot(contains('环比')));
      // 不给 0 分钟这种会误导的基线数字
      expect(p.user, isNot(contains('上周同期：0')));
      expect(p.user, contains('不要据此判断增减趋势'));
    });

    test('部分周如实声明（08-A1）：不允许把半周当整周判断', () {
      final p = buildPrompt(insight());
      expect(p.user, contains('进行中的部分周'));
      expect(p.user, contains('共 3 天'));
    });

    test('记忆注入位置（看板 #54）：事实块 → 记忆 → 任务', () {
      const block = '$kMemoryBlockHeader\n- 09-25（周五）：专注 40 分钟';
      final p = buildPrompt(insight(), memory: block);
      final memoryAt = p.user.indexOf(kMemoryBlockHeader);
      expect(memoryAt, greaterThan(p.user.indexOf('本周专注')));
      expect(p.user.indexOf('请输出：'), greaterThan(memoryAt));
      expect(p.user, contains('专注 40 分钟'));
    });

    test('无记忆时消息与未引入记忆功能时逐字符一致（记忆是增强不是必需）', () {
      final plain = buildPrompt(insight()).user;
      expect(plain, isNot(contains(kMemoryBlockHeader)));
      expect(buildPrompt(insight(), memory: null).user, plain);
    });

    test('system 硬约束含「记忆不得混算」（与注入块表头配套）', () {
      final s = buildPrompt(insight(), memory: 'x').system!;
      expect(s, contains('近 7 日记忆'));
      expect(s, contains('不要与本次数据混算'));
    });

    test('硬约束落在 system 消息（08-A5）', () {
      final p = buildPrompt(insight());
      expect(p.system, isNotNull);
      expect(p.system, contains('原样引用'));
      expect(p.system, contains('不得自行计算'));
      expect(p.system, contains('加油')); // 反鸡汤条款
      expect(p.system, contains('加粗')); // 格式条款（减少 Markdown 依赖）
      // user 消息只承载数据与任务，不再重复角色设定
      expect(p.user, isNot(contains('你是一位')));
    });

    test('08-B3 新洞察字段全部进入事实块', () {
      final p = buildPrompt(insight());
      // 中断：次数 / 总时长 / 占比 / 单次均值（同行合并，模型一眼能看出分量）
      expect(p.user, contains('中断：6 次，共 32 分钟（占专注时长 5%，单次平均 5 分钟）'));
      expect(p.user, contains('中断时段分布（按次数）：晚上 67%、下午 33%'));
      // 最长一段 + 所在时段
      expect(p.user, contains('最长连续一段：50 分钟（出现在下午）'));
      // 最专注的一天 + 有记录天数
      expect(p.user, contains('最专注的一天：周三 240 分钟'));
      expect(p.user, contains('有专注记录的天数：3 天'));
    });

    test('调性重构：system 里「禁空洞」与「要具体」并存（看板 #53）', () {
      final s = buildPrompt(insight()).system!;
      // 反鸡汤条款不能因为改调性而丢掉——只禁「没有信息量」的表达
      expect(s, contains('没有信息量的评价与鼓励语'));
      expect(s, contains('加油'));
      // 「要具体」才是解「枯燥」的那一半（08-A5 那版只有「禁」没有「要」）
      expect(s, contains('至少给出一处数字之间的关系'));
      expect(s, contains('第一句必须是「发现」'));
      expect(s, contains('可以说人话'));
    });

    test('缓存指纹带提示词版本：口径变更同样提示刷新', () {
      expect(cacheFingerprintOf('1|2|3|4'), '1|2|3|4@$kPromptVersion');
    });

    test('周报预算 600 tokens（08-A4）', () {
      expect(buildPrompt(insight()).maxTokens, kWeeklyMaxTokens);
    });

    test('脏数据扫描：prompt 不含白名单外字段样式内容', () {
      final p = buildPrompt(insight());
      final raw = '${p.system}\n${p.user}';
      expect(raw, isNot(contains('com.')));
      expect(raw, isNot(contains('imei')));
      expect(raw, isNot(contains('device')));
    });
  });

  group('parseInsightResponse', () {
    test('正常格式：3 段复盘 + 1 条建议', () {
      final result = parseInsightResponse(
        '本周专注 620 分钟，状态不错。\n\n'
        '上午是你的黄金时段。\n\n'
        '连续 5 天值得保持。\n\n'
        '建议：下周把最难的任务固定在上午。',
      );
      expect(result, isNotNull);
      expect(result!.paragraphs, hasLength(3));
      expect(result.suggestion, '下周把最难的任务固定在上午。');
    });

    test('超过 3 段复盘：截断到 3 段', () {
      final result = parseInsightResponse(
        '第一段。\n\n第二段。\n\n第三段。\n\n第四段。\n\n建议：早点开始。',
      );
      expect(result, isNotNull);
      expect(result!.paragraphs, hasLength(3));
      expect(result.suggestion, '早点开始。');
    });

    test('少于 3 段也接受（1 段 + 建议）', () {
      final result = parseInsightResponse('只有一段。\n\n建议：继续保持。');
      expect(result!.paragraphs, hasLength(1));
    });

    test('没有建议段 → null（整体降级）', () {
      expect(parseInsightResponse('只有复盘没有建议。'), isNull);
    });

    test('空串/乱文 → null', () {
      expect(parseInsightResponse(''), isNull);
      expect(parseInsightResponse('   \n\n  '), isNull);
    });

    // ------------------------------------------------ 08-A3 加固用例

    test('单换行分段（模型不用空行）也能解析', () {
      final result = parseInsightResponse(
        '第一段。\n第二段。\n第三段。\n建议：早点开始。',
      );
      expect(result, isNotNull, reason: '单换行分段不应导致整体降级');
      expect(result!.paragraphs, hasLength(3));
      expect(result.suggestion, '早点开始。');
    });

    test('Markdown 加粗的建议段也能识别', () {
      final result = parseInsightResponse('本周不错。\n\n**建议：** 把难事放上午。');
      expect(result, isNotNull);
      expect(result!.suggestion, '把难事放上午。');
    });

    test('列表/引用/标题前缀的建议段也能识别', () {
      for (final line in ['- 建议：早点开始。', '> 建议：早点开始。', '## 建议：早点开始。']) {
        final result = parseInsightResponse('复盘一段。\n\n$line');
        expect(result, isNotNull, reason: '未识别：$line');
        expect(result!.suggestion, '早点开始。');
      }
    });

    test('建议与上一段挤在同一块（无空行）也能拆出来', () {
      final result = parseInsightResponse('第一段。\n第二段。\n建议：早点开始。');
      expect(result, isNotNull);
      expect(result!.suggestion, '早点开始。');
      expect(result.paragraphs, isNotEmpty);
    });

    test('Markdown 装饰从复盘段落里被清掉', () {
      final result = parseInsightResponse(
        '**本周专注 620 分钟。**\n\n- 上午状态最好。\n\n建议：保持。',
      );
      expect(result, isNotNull);
      expect(result!.paragraphs, contains('本周专注 620 分钟。'));
      expect(result.paragraphs, contains('上午状态最好。'));
    });
  });
}
