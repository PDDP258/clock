/// 「问 AI 一句」点选问答区（看板 #50/#51）：统计页（周报题）与
/// 详细时间统计页（当日题）共用。
///
/// - 仅 AI 总开关开启时渲染；未配 Key/未同意时点按静默无反应
///   （设置页是配置入口，此处不打扰——ADR-0006 安静原则）；
/// - 单槽状态：只展示属于本组件题目集合的回答/转圈（周报题与当日题
///   分属两页，互不串台）；
/// - 回答旁「换一句」= force 跳缓存重新提问。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/ai_ask.dart';
import '../application/ai_controller.dart';

/// 点选问答区。
class AiAskChips extends ConsumerWidget {
  const AiAskChips({super.key, required this.questions, this.day});

  /// 本区展示的题目集合
  final List<AiAskQuestion> questions;

  /// 当日场景的查看日（周报场景传 null）
  final DateTime? day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiEnabled = ref.watch(aiSettingsProvider.select((s) => s.enabled));
    if (!aiEnabled) return const SizedBox.shrink();

    final state = ref.watch(aiAskProvider);
    final theme = Theme.of(context);
    // 单槽状态只认本组件的题目
    final ownsState =
        state.qid != null && questions.any((q) => q.id == state.qid);
    final showLoading = state.loading && ownsState;
    final showAnswer = !state.loading && ownsState && state.text != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('问 AI 一句',
            style: TextStyle(
                fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final q in questions)
              ActionChip(
                label: Text(q.label, style: const TextStyle(fontSize: 13)),
                onPressed: state.loading
                    ? null
                    : () => ref.read(aiAskProvider.notifier).ask(q, day: day),
              ),
          ],
        ),
        if (showLoading) ...[
          const SizedBox(height: 8),
          const Row(children: [
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 6),
            Text('AI 思考中…', style: TextStyle(fontSize: 13)),
          ]),
        ] else if (showAnswer) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(state.text!,
                    style: const TextStyle(fontSize: 13, height: 1.4)),
              ),
              // 换一句：跳过缓存重新提问
              TextButton(
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () {
                  final q =
                      questions.where((q) => q.id == state.qid).first;
                  ref
                      .read(aiAskProvider.notifier)
                      .ask(q, day: day, force: true);
                },
                child: const Text('换一句', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
